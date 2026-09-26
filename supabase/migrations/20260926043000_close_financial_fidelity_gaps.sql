-- Diagnostic events are intentionally client-denied. The mobile client uploads
-- diagnostics through the authenticated Edge Function/service-role boundary;
-- direct table reads/writes must remain unavailable even when RLS is enabled.
alter table public.diagnostic_events enable row level security;
drop policy if exists diagnostic_events_client_deny on public.diagnostic_events;
create policy diagnostic_events_client_deny
  on public.diagnostic_events
  for all
  to anon, authenticated
  using (false)
  with check (false);

-- Close financial fidelity gaps: first-class split sale payments and
-- server-authoritative return/refund accounting.
--
-- Existing V1 RPCs remain intact for backward compatibility. New clients use
-- the V2 service wrappers below; both are idempotent by business+operation.

-- Monetary fields are standardized to the same 2-decimal contract used by the
-- rest of the financial schema. Existing production income values are already
-- <= 500000 and have zero fractional cents, so this is a lossless tightening.
alter table public.income_records
  alter column amount type numeric(14,2)
  using round(amount,2);

create or replace function public.fulus_api_create_sale_atomic_v2(
  target_user_id uuid,
  target_business_id uuid,
  target_location_id uuid,
  target_customer_id uuid,
  target_client_reference text,
  target_sale_date timestamptz,
  target_discount numeric,
  target_tax numeric,
  target_amount_paid numeric,
  target_payment_method text,
  target_notes text,
  target_device_id uuid,
  target_items jsonb,
  target_payments jsonb
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
  sale_id uuid;
  payment_id uuid;
  item jsonb;
  payment jsonb;
  total numeric;
  payment_total numeric := 0;
  cash_paid numeric := 0;
  credit_paid numeric := 0;
  payment_method text;
  payment_index integer := 0;
  payment_inserted boolean;

  method text;
  amount numeric;
begin
  if target_payments is null or jsonb_array_length(target_payments)=0 then
    raise exception using errcode='22023',message='Sale requires payment legs';
  end if;

  for payment in select * from jsonb_array_elements(target_payments) loop
    method := lower(trim(payment->>'method'));
    amount := round((payment->>'amount')::numeric,2);
    if method is null or method='' or amount<=0 then
      raise exception using errcode='22023',message='Invalid sale payment leg';
    end if;
    if method='credit' then
      credit_paid := credit_paid + amount;
    else
      cash_paid := cash_paid + amount;
    end if;
    payment_total := payment_total + amount;
  end loop;

  if payment_total <= 0 then
    raise exception using errcode='22023',message='Sale payment total must be positive';
  end if;

  payment_method := case
    when (select count(distinct lower(trim(value->>'method')))
          from jsonb_array_elements(target_payments) value)=1
      then lower(trim((target_payments->0)->>'method'))
    else 'split'
  end;

  request_hash := md5(jsonb_build_object(
    'location_id',target_location_id,
    'customer_id',target_customer_id,
    'client_reference',target_client_reference,
    'sale_date',target_sale_date,
    'discount',target_discount,
    'tax',target_tax,
    'amount_paid',cash_paid,
    'payment_method',payment_method,
    'notes',target_notes,
    'device_id',target_device_id,
    'items',target_items,
    'payments',target_payments
  )::text);

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,target_client_reference,
    'sale.create.v2',request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id and key=target_client_reference
  for update;

  if idem.operation_type<>'sale.create.v2' or idem.request_hash<>request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;

  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  perform set_config('request.jwt.claim.sub',target_user_id::text,true);

  result := public.create_sale_atomic(
    target_business_id,target_location_id,target_customer_id,
    target_client_reference,target_sale_date,target_discount,target_tax,
    cash_paid,payment_method,target_notes,target_device_id,target_items
  );

  if coalesce((result->>'status'),'')='applied' then
    sale_id := (result->>'sale_id')::uuid;
    total := round((result->>'total')::numeric,2);

    if abs(payment_total-total) > 0.01 then
      raise exception using errcode='22023',message='Payment legs must equal the server-calculated sale total';
    end if;

    if abs((result->>'amount_paid')::numeric-cash_paid) > 0.01 then
      raise exception using errcode='22023',message='Server paid amount does not match payment legs';
    end if;

    if abs((result->>'balance_due')::numeric-credit_paid) > 0.01 then
      raise exception using errcode='22023',message='Credit leg does not match server balance due';
    end if;

    for payment in select * from jsonb_array_elements(target_payments) loop
      method := lower(trim(payment->>'method'));
      amount := round((payment->>'amount')::numeric,2);
      payment_index := payment_index + 1;

      insert into public.sale_payments(
        business_id,sale_id,amount,payment_method,operation_id,created_by,device_id
      )
      values(
        target_business_id,sale_id,amount,method,
        target_client_reference||':payment:'||payment_index,
        target_user_id,target_device_id
      )
      on conflict(business_id,operation_id) do nothing
      returning id into payment_id;

      payment_inserted := payment_id is not null;
      if payment_inserted then
        perform public._fulus_append_change(
          target_business_id,'sale',sale_id,'upsert',
          jsonb_build_object(
            'id',sale_id,
            'payment_id',payment_id,
            'payment_method',method,
            'payment_amount',amount
          )
        );

        if method <> 'credit' then
          insert into public.cash_ledger(
            business_id,location_id,entry_type,amount,direction,
            reference_id,operation_id,created_by,device_id
          )
          values(
            target_business_id,target_location_id,'sale',amount,'in',sale_id,
            target_client_reference||':cash:'||payment_index,
            target_user_id,target_device_id
          )
          on conflict(business_id,operation_id) do nothing;
        end if;
      end if;
    end loop;
  end if;

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$function$;

create or replace function public.fulus_api_create_return_atomic_v2(
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
      select * into si
      from public.sale_items
      where sale_id=target_sale_id
        and product_id=(item->>'product_id')::uuid
      order by id
      limit 1
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

    line := round((item->>'quantity')::numeric*si.unit_price,2);
    return_value := return_value + line;

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

  sale_credit_balance := greatest(round(sale.total-sale.amount_paid,2),0);

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

    if credit_reversal > 0 then
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
    end if;
  end if;

  cash_refund := round(return_value-credit_reversal,2);

  if method='credit' then
    if credit_reversal <= 0 then
      raise exception using errcode='22023',message='Credit refund must be positive';
    end if;
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

revoke execute on function public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb) to service_role;
grant execute on function public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb) to service_role;
