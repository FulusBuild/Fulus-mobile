-- Return refunds must be allocated from the authoritative sale total,
-- not raw pre-discount line prices. The sale total already includes the
-- sale-level discount and tax, so proportional allocation preserves the
-- financial contract for partial and multi-line returns.
--
-- Keep this as a final CREATE OR REPLACE migration rather than rewriting
-- historical migrations: Supabase applies migrations in order and the
-- deployed function definition is the authoritative runtime contract.

create or replace function public.fulus_api_create_return_atomic_v2_unchecked(
  target_user_id uuid,
  target_business_id uuid,
  target_sale_id uuid,
  target_client_reference text,
  target_reason text,
  target_refund_amount numeric,
  target_refund_method text,
  target_device_id uuid,
  target_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
  existing public.returns%rowtype;
  rid uuid;
  item jsonb;
  si public.sale_items%rowtype;
  product public.products%rowtype;
  sale public.sales%rowtype;
  line numeric;
  return_value numeric := 0;
  previously_refunded numeric := 0;
  remaining_refundable numeric;
  sale_subtotal numeric;
  credit_reversal numeric := 0;
  cash_refund numeric := 0;
  customer_balance numeric;
  sale_credit_balance numeric;
  ledger_id uuid;
  movement_id uuid;
  current_quantity integer;
  returned_quantity integer;
  method text := lower(trim(coalesce(target_refund_method,'')));
begin
  if method not in ('cash','card','mobile_money','credit') then
    raise exception using errcode='22023',message='Unsupported refund method';
  end if;

  if target_items is null or jsonb_array_length(target_items)=0 then
    raise exception using errcode='22023',message='Return requires items';
  end if;

  select * into sale
  from public.sales
  where id=target_sale_id and business_id=target_business_id
  for update;

  if sale.id is null then
    raise exception using errcode='22023',message='Sale not found';
  end if;

  sale_subtotal := round(coalesce(sale.subtotal,0),2);
  select coalesce(sum(ri.amount),0)::numeric into previously_refunded
  from public.return_items ri
  join public.returns r on r.id=ri.return_id
  where r.sale_id=sale.id;

  if previously_refunded >= greatest(round(coalesce(sale.total,0),2),0) then
    raise exception using errcode='22023',message='Sale has no refundable balance remaining';
  end if;

  request_hash := md5(jsonb_build_object(
    'sale_id',target_sale_id,
    'client_reference',target_client_reference,
    'reason',target_reason,
    'refund_amount',target_refund_amount,
    'refund_method',method,
    'device_id',target_device_id,
    'items',target_items
  )::text);

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,target_client_reference,
    'return.create.v2',request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id and key=target_client_reference
  for update;

  if idem.operation_type<>'return.create.v2' or idem.request_hash<>request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;

  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  -- The Edge Function invokes this SECURITY DEFINER RPC as the service actor.
  -- Bind the verified end-user before permission evaluation so has_permission()
  -- authorizes the actual business member rather than the service role.
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  perform public.require_sale_location_access(target_business_id,target_sale_id);

  if not public.has_permission(target_business_id,'returns.create') then
    raise exception using errcode='42501',message='Return permission required';
  end if;

  insert into public.returns(
    business_id,sale_id,customer_id,client_reference,refund_amount,
    reason,created_by,device_id
  )
  values(
    target_business_id,sale.id,sale.customer_id,target_client_reference,
    round(coalesce(target_refund_amount,0),2),trim(target_reason),
    target_user_id,target_device_id
  )
  returning id into rid;

  for item in select * from jsonb_array_elements(target_items) loop
    if nullif(trim(item->>'sale_item_id'),'') is not null then
      select * into si
      from public.sale_items
      where id=(item->>'sale_item_id')::uuid and sale_id=target_sale_id
      for update;
    else
      if (select count(*) from public.sale_items
          where sale_id=target_sale_id
            and product_id=(item->>'product_id')::uuid) <> 1 then
        raise exception using errcode='22023',
          message='Return item must identify an unambiguous sale item';
      end if;
      select * into si
      from public.sale_items
      where sale_id=target_sale_id
        and product_id=(item->>'product_id')::uuid
      for update;
    end if;

    if si.id is null then
      raise exception using errcode='22023',message='Invalid return item';
    end if;

    select coalesce(sum(ri.quantity),0)::integer into returned_quantity
    from public.return_items ri
    where ri.sale_item_id=si.id;

    if (item->>'quantity')::integer<=0
       or (item->>'quantity')::integer > (si.quantity-returned_quantity) then
      raise exception using errcode='22023',message='Invalid return quantity';
    end if;

    if sale_subtotal <= 0 or coalesce(sale.total,0) <= 0 then
      line := 0;
    else
      -- Allocate the authoritative paid sale total (after discount + tax)
      -- proportionally across original line value, then apply the returned
      -- quantity. This keeps refunds from exceeding what the customer
      -- actually paid/owes on the sale while remaining deterministic for
      -- partial-line returns.
      line := round(
        (item->>'quantity')::numeric * si.unit_price
        * sale.total / sale_subtotal / greatest(si.quantity,1),
        2
      );
    end if;
    remaining_refundable := greatest(
      round(sale.total - previously_refunded - return_value,2),
      0
    );
    line := least(line, remaining_refundable);
    return_value := round(return_value + line,2);

    insert into public.return_items(
      return_id,sale_item_id,product_id,quantity,amount
    )
    values(
      rid,si.id,si.product_id,(item->>'quantity')::integer,line
    );

    select * into product from public.products where id=si.product_id;

    if product.tracks_stock then
      update public.product_stock_levels
      set current_stock=current_stock+(item->>'quantity')::integer,updated_at=now()
      where product_id=si.product_id and location_id=sale.location_id;

      insert into public.inventory_movements(
        business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id
      )
      values(
        target_business_id,si.product_id,sale.location_id,(item->>'quantity')::integer,
        'return',target_client_reference||':stock:'||si.id,target_user_id,target_device_id
      )
      returning id into movement_id;

      select current_stock into current_quantity
      from public.product_stock_levels
      where product_id=si.product_id and location_id=sale.location_id;

      perform public._fulus_append_change(
        target_business_id,'stock_movement',movement_id,'upsert',
        jsonb_build_object(
          'id',movement_id,'product_id',si.product_id,'location_id',sale.location_id,
          'quantity_delta',(item->>'quantity')::integer,
          'quantity',(item->>'quantity')::integer,
          'new_quantity',current_quantity,'movement_type','return','reason','return'
        )
      );
    end if;
  end loop;

  return_value := round(return_value,2);
  if abs(coalesce(target_refund_amount,0)-return_value) > 0.01 then
    raise exception using errcode='22023',message='Refund amount must equal the server-calculated returned value';
  end if;

  -- For split payments, credit extended is the explicit credit payment
  -- legs. Falling back to total - amount_paid preserves compatibility with
  -- legacy single-method credit sales that have no SalePayments rows.
  select greatest(round(coalesce(sum(sp.amount), sale.total-sale.amount_paid),2),0)
  into sale_credit_balance
  from public.sale_payments sp
  where sp.business_id=target_business_id
    and sp.sale_id=sale.id
    and lower(trim(sp.payment_method))='credit';

  if method='credit' then
    if sale.customer_id is null then
      raise exception using errcode='22023',message='Credit refund requires a customer';
    end if;
    select outstanding_balance into customer_balance
    from public.customers
    where id=sale.customer_id and business_id=target_business_id
    for update;
    if coalesce(customer_balance,0) <= 0 then
      raise exception using errcode='22023',message='Credit refund requires an outstanding customer balance';
    end if;
    credit_reversal := return_value;
    elsif sale.customer_id is not null and sale_credit_balance > 0 then
    select outstanding_balance into customer_balance
    from public.customers
    where id=sale.customer_id and business_id=target_business_id
    for update;

    credit_reversal := least(
      return_value,
      sale_credit_balance,
      greatest(coalesce(customer_balance,0),0)
    );


  end if;

  cash_refund := round(return_value-credit_reversal,2);

  if method='credit' then
    if credit_reversal <> return_value
       or return_value > sale_credit_balance
       or return_value > greatest(coalesce(customer_balance,0),0) then
      raise exception using errcode='22023',
        message='Account-credit refund must fully reverse an eligible customer credit balance';
    end if;

    update public.customers
    set outstanding_balance=round(outstanding_balance-credit_reversal,2),
        updated_at=now()
    where id=sale.customer_id;

    insert into public.customer_ledger_entries(
      business_id,customer_id,sale_id,amount,operation_id,entry_type,
      created_by,device_id,note
    )
    values(
      target_business_id,sale.customer_id,sale.id,credit_reversal,
      target_client_reference||':credit-reversal','credit_reversal',
      target_user_id,target_device_id,'Return credit reversal'
    )
    returning id into ledger_id;

    perform public._fulus_append_change(
      target_business_id,'customer_ledger',ledger_id,'upsert',
      jsonb_build_object(
        'id',ledger_id,'customer_id',sale.customer_id,
        'entry_type','credit_reversal','amount',credit_reversal
      )
    );
  else
    if cash_refund <= 0 then
      raise exception using errcode='22023',message='Refund is fully settled by reversing customer credit';
    end if;

    insert into public.cash_ledger(
      business_id,location_id,entry_type,amount,direction,reference_id,
      operation_id,created_by,device_id
    )
    values(
      target_business_id,sale.location_id,'refund',cash_refund,'out',rid,
      target_client_reference||':cash',target_user_id,target_device_id
    )
    on conflict(business_id,operation_id) do nothing;
  end if;

  perform public._fulus_append_change(
    target_business_id,'return',rid,'upsert',
    jsonb_build_object(
      'id',rid,'sale_id',sale.id,'refund_amount',return_value,
      'refund_method',method,'credit_reversal',credit_reversal,
      'cash_refund',cash_refund,'status','completed'
    )
  );

  result := jsonb_build_object(
    'status','applied','return_id',rid,'refund_amount',return_value,
    'refund_method',method,'credit_reversal',credit_reversal,
    'cash_refund',cash_refund,'server_authoritative',true
  );

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$function$;

