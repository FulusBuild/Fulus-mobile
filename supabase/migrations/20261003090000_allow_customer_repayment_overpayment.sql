-- Customer repayments are allowed to exceed the outstanding balance.
-- The local customer-credit engine deliberately caps the balance at zero and
-- returns the excess for explicit user feedback. Keep the cloud mutation
-- contract identical so an offline repayment cannot be rejected after sync.

create or replace function public.record_customer_repayment(
  target_business_id uuid,
  target_customer_id uuid,
  target_amount numeric,
  target_operation_id text,
  target_payment_method text default null,
  target_note text default null,
  target_device_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();
  existing public.customer_ledger_entries%rowtype;
  eid uuid;
  old_balance numeric;
  new_balance numeric;
  excess_amount numeric;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;

  if not public.has_permission(target_business_id, 'credit.manage') then
    raise exception using errcode='42501', message='Credit management permission required';
  end if;

  if target_amount <= 0 then
    raise exception using errcode='22023', message='Repayment amount must be positive';
  end if;

  select *
  into existing
  from public.customer_ledger_entries
  where business_id = target_business_id
    and operation_id = target_operation_id
    and entry_type = 'repayment';

  if existing.id is not null then
    select outstanding_balance
    into new_balance
    from public.customers
    where id = target_customer_id;

    return jsonb_build_object(
      'status', 'already_applied',
      'ledger_id', existing.id,
      'new_balance', coalesce(new_balance, 0),
      'excess_amount', 0,
      'server_authoritative', true
    );
  end if;

  select outstanding_balance
  into old_balance
  from public.customers
  where id = target_customer_id
    and business_id = target_business_id
    and is_active = true
  for update;

  if old_balance is null then
    raise exception using errcode='22023', message='Customer does not belong to business';
  end if;

  -- Volume 7 rule: repayment is recorded even when it exceeds what is owed.
  -- The outstanding balance is capped at zero and the excess is surfaced to
  -- the caller instead of being silently discarded.
  new_balance := round(greatest(old_balance - target_amount, 0), 2);
  excess_amount := round(greatest(target_amount - old_balance, 0), 2);

  if target_device_id is not null
     and not exists (
       select 1
       from public.devices
       where id = target_device_id
         and business_id = target_business_id
         and status = 'active'
     ) then
    raise exception using errcode='42501', message='Device is not active for this business';
  end if;

  update public.customers
  set outstanding_balance = new_balance,
      updated_at = now()
  where id = target_customer_id;

  insert into public.customer_ledger_entries(
    business_id,
    customer_id,
    amount,
    operation_id,
    entry_type,
    payment_method,
    note,
    created_by,
    device_id
  )
  values(
    target_business_id,
    target_customer_id,
    target_amount,
    target_operation_id,
    'repayment',
    target_payment_method,
    target_note,
    actor,
    target_device_id
  )
  returning id into eid;

  perform public._fulus_append_change(
    target_business_id,
    'customer_ledger',
    eid,
    'upsert',
    jsonb_build_object(
      'id', eid,
      'customer_id', target_customer_id,
      'entry_type', 'repayment',
      'amount', target_amount,
      'new_balance', new_balance,
      'operation_id', target_operation_id
    )
  );

  return jsonb_build_object(
    'status', 'applied',
    'ledger_id', eid,
    'new_balance', new_balance,
    'excess_amount', excess_amount,
    'server_authoritative', true
  );
end;
$function$;

revoke execute on function public.record_customer_repayment(
  uuid, uuid, numeric, text, text, text, uuid
) from public, anon, authenticated, service_role;
