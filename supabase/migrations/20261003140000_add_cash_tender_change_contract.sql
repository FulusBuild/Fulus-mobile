alter table public.sales add column if not exists cash_tendered numeric(14,2) not null default 0;
alter table public.sales add column if not exists cash_change numeric(14,2) not null default 0;
alter table public.sale_payments add column if not exists tendered_amount numeric(14,2);

update public.sale_payments set tendered_amount=amount where tendered_amount is null;

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
  cash_applied numeric := 0;
  credit_paid numeric := 0;
  payment_method text;
  payment_index integer := 0;
  payment_inserted boolean;
  tendered_amount numeric;
  cash_tendered_total numeric := 0;
  cash_change_total numeric := 0;

  method text;
  amount numeric;
begin
  if target_payments is null or jsonb_array_length(target_payments)=0 then
    raise exception using errcode='22023',message='Sale requires payment legs';
  end if;

  for payment in select * from jsonb_array_elements(target_payments) loop
    method := lower(trim(payment->>'method'));
    amount := round((payment->>'amount')::numeric,2);
    tendered_amount := round(coalesce((payment->>'tendered_amount')::numeric, amount),2);
    if method is null or method='' or amount<=0 or tendered_amount < amount then
      raise exception using errcode='22023',message='Invalid sale payment leg';
    end if;
    if method='credit' then
      if tendered_amount <> amount then
        raise exception using errcode='22023',message='Credit payment cannot have a separate tendered amount';
      end if;
      credit_paid := credit_paid + amount;
    else
      cash_paid := cash_paid + amount;
      if method='cash' then
        cash_applied := cash_applied + amount;
        cash_tendered_total := cash_tendered_total + tendered_amount;
      elsif tendered_amount <> amount then
        raise exception using errcode='22023',message='Non-cash payment tender must equal applied amount';
      end if;
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
    'payments',target_payments,
    'cash_tendered',cash_tendered_total
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

    cash_change_total := round(cash_tendered_total-cash_applied,2);
    if cash_change_total < 0 then
      raise exception using errcode='22023',message='Cash tendered cannot be less than applied cash';
    end if;

    if abs((result->>'balance_due')::numeric-credit_paid) > 0.01 then
      raise exception using errcode='22023',message='Credit leg does not match server balance due';
    end if;

    update public.sales s
    set cash_tendered=cash_tendered_total,
        cash_change=cash_change_total,
        updated_at=now()
    where s.id=sale_id;

    for payment in select * from jsonb_array_elements(target_payments) loop
      method := lower(trim(payment->>'method'));
      amount := round((payment->>'amount')::numeric,2);
      tendered_amount := round(coalesce((payment->>'tendered_amount')::numeric, amount),2);
      payment_index := payment_index + 1;

      insert into public.sale_payments(
        business_id,sale_id,amount,tendered_amount,payment_method,operation_id,created_by,device_id
      )
      values(
        target_business_id,sale_id,amount,tendered_amount,method,
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
            'payment_amount',amount,
            'tendered_amount',tendered_amount,
            'change_amount',case when method='cash' then greatest(tendered_amount-amount,0) else 0 end
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
