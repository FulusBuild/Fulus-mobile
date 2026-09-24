create or replace function public.record_sale_payment(
  target_business_id uuid,
  target_sale_id uuid,
  target_amount numeric,
  target_operation_id text,
  target_payment_method text,
  target_device_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  existing public.sale_payments%rowtype;
  pid uuid;
  sale public.sales%rowtype;
  new_paid numeric;
  remaining numeric;
  new_customer_balance numeric;
begin
  if actor is null or not public.has_permission(target_business_id,'sales.create') then
    raise exception using errcode='42501',message='Sales permission required';
  end if;

  select * into existing
  from public.sale_payments
  where business_id=target_business_id
    and operation_id=target_operation_id;

  if existing.id is not null then
    return jsonb_build_object('status','already_applied','payment_id',existing.id);
  end if;

  select * into sale
  from public.sales
  where id=target_sale_id and business_id=target_business_id
  for update;

  if sale.id is null then
    raise exception using errcode='22023',message='Sale not found';
  end if;

  remaining:=sale.total-sale.amount_paid;

  if target_amount<=0 or target_amount>remaining then
    raise exception using errcode='22023',message='Payment exceeds sale balance';
  end if;

  insert into public.sale_payments(
    business_id,sale_id,amount,payment_method,operation_id,created_by,device_id
  )
  values(
    target_business_id,target_sale_id,target_amount,target_payment_method,
    target_operation_id,actor,target_device_id
  )
  returning id into pid;

  new_paid:=sale.amount_paid+target_amount;

  update public.sales
  set amount_paid=new_paid,updated_at=now()
  where id=sale.id;

  if sale.customer_id is not null then
    update public.customers
    set outstanding_balance=round(outstanding_balance-target_amount,2),
        updated_at=now()
    where id=sale.customer_id
      and business_id=target_business_id
      and is_active=true
      and outstanding_balance>=target_amount
    returning outstanding_balance into new_customer_balance;

    if new_customer_balance is null then
      raise exception using errcode='22023',
        message='Customer outstanding balance is insufficient for payment';
    end if;
  end if;

  if target_payment_method is not null then
    insert into public.cash_ledger(
      business_id,location_id,entry_type,amount,direction,reference_id,
      operation_id,created_by,device_id
    )
    values(
      target_business_id,sale.location_id,'sale',target_amount,'in',sale.id,
      target_operation_id||':cash',actor,target_device_id
    );
  end if;

  perform public._fulus_append_change(
    target_business_id,'sale',sale.id,'upsert',
    jsonb_build_object(
      'id',sale.id,'amount_paid',new_paid,'balance_due',sale.total-new_paid
    )
  );

  return jsonb_build_object(
    'status','applied',
    'payment_id',pid,
    'amount_paid',new_paid,
    'balance_due',sale.total-new_paid,
    'customer_balance',new_customer_balance,
    'server_authoritative',true
  );
end
$function$;

revoke all on function public.record_sale_payment(
  uuid,uuid,numeric,text,text,uuid
) from public, anon, authenticated, service_role;

grant execute on function public.record_sale_payment(
  uuid,uuid,numeric,text,text,uuid
) to service_role;
