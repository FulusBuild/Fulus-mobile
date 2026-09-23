-- Enforce cumulative return eligibility per sale item.
-- A sale line's original quantity is the upper bound across all successful
-- returns, not independently for every return request.
create or replace function public.create_return_atomic(target_business_id uuid, target_sale_id uuid, target_client_reference text, target_reason text, target_refund_amount numeric, target_device_id uuid, target_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor uuid:=auth.uid();
  existing public.returns%rowtype;
  rid uuid;
  item jsonb;
  si public.sale_items%rowtype;
  product public.products%rowtype;
  line numeric;
  sale public.sales%rowtype;
  customer_balance numeric;
  reversal numeric:=0;
  ledger_id uuid;
  movement_id uuid;
  current_quantity integer;
  returned_quantity integer;
begin
  if actor is null or not public.has_permission(target_business_id,'returns.create') then
    raise exception using errcode='42501',message='Return permission required';
  end if;

  select * into existing from public.returns
  where business_id=target_business_id and client_reference=target_client_reference;

  if existing.id is not null then
    return jsonb_build_object('status','already_applied','return_id',existing.id);
  end if;

  if target_items is null or jsonb_array_length(target_items)=0 then
    raise exception using errcode='22023',message='Return requires items';
  end if;

  select * into sale from public.sales
  where id=target_sale_id and business_id=target_business_id
  for update;

  if sale.id is null then
    raise exception using errcode='22023',message='Sale not found';
  end if;

  insert into public.returns(business_id,sale_id,customer_id,client_reference,refund_amount,reason,created_by,device_id)
  values(target_business_id,sale.id,sale.customer_id,target_client_reference,coalesce(target_refund_amount,0),trim(target_reason),actor,target_device_id)
  returning id into rid;

  for item in select * from jsonb_array_elements(target_items) loop
    select * into si from public.sale_items
    where id=(item->>'sale_item_id')::uuid and sale_id=target_sale_id;

    if si.id is null then
      raise exception using errcode='22023',message='Invalid return item or quantity';
    end if;

    select coalesce(sum(ri.quantity),0)::integer into returned_quantity
    from public.return_items ri
    where ri.sale_item_id=si.id;

    if (item->>'quantity')::integer<=0
       or (item->>'quantity')::integer > (si.quantity-returned_quantity) then
      raise exception using errcode='22023',message='Invalid return item or quantity';
    end if;

    line:=round((item->>'quantity')::numeric*si.unit_price,2);

    insert into public.return_items(return_id,sale_item_id,product_id,quantity,amount)
    values(rid,si.id,si.product_id,(item->>'quantity')::integer,line);

    select * into product from public.products where id=si.product_id;

    if product.tracks_stock then
      update public.product_stock_levels
      set current_stock=current_stock+(item->>'quantity')::integer,updated_at=now()
      where product_id=si.product_id and location_id=sale.location_id;

      insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
      values(target_business_id,si.product_id,sale.location_id,(item->>'quantity')::integer,'return',target_client_reference||':stock:'||si.id,actor,target_device_id)
      returning id into movement_id;

      select current_stock into current_quantity
      from public.product_stock_levels
      where product_id=si.product_id and location_id=sale.location_id;

      perform public._fulus_append_change(
        target_business_id,'stock_movement',movement_id,'upsert',
        jsonb_build_object(
          'id',movement_id,
          'product_id',si.product_id,
          'location_id',sale.location_id,
          'quantity_delta',(item->>'quantity')::integer,
          'quantity',(item->>'quantity')::integer,
          'new_quantity',current_quantity,
          'movement_type','return',
          'reason','return'
        )
      );
    end if;

    reversal:=reversal+line;
  end loop;

  reversal:=least(reversal,sale.total);

  if sale.customer_id is not null and reversal>0 then
    select outstanding_balance into customer_balance
    from public.customers where id=sale.customer_id for update;

    if customer_balance is not null and customer_balance>0 then
      reversal:=least(reversal,customer_balance);
      update public.customers
      set outstanding_balance=round(outstanding_balance-reversal,2),updated_at=now()
      where id=sale.customer_id;

      insert into public.customer_ledger_entries(business_id,customer_id,sale_id,amount,operation_id,entry_type,created_by,device_id,note)
      values(target_business_id,sale.customer_id,sale.id,reversal,target_client_reference||':credit-reversal','credit_reversal',actor,target_device_id,'Return credit reversal')
      returning id into ledger_id;

      perform public._fulus_append_change(
        target_business_id,'customer_ledger',ledger_id,'upsert',
        jsonb_build_object('id',ledger_id,'customer_id',sale.customer_id,'entry_type','credit_reversal','amount',reversal)
      );
    end if;
  end if;

  if coalesce(target_refund_amount,0)>0 then
    insert into public.cash_ledger(business_id,location_id,entry_type,amount,direction,reference_id,operation_id,created_by,device_id)
    values(target_business_id,sale.location_id,'refund',target_refund_amount,'out',rid,target_client_reference||':cash',actor,target_device_id);
  end if;

  perform public._fulus_append_change(
    target_business_id,'return',rid,'upsert',
    jsonb_build_object('id',rid,'sale_id',sale.id,'refund_amount',target_refund_amount,'status','completed')
  );

  return jsonb_build_object('status','applied','return_id',rid,'credit_reversal',reversal,'server_authoritative',true);
end
$function$;