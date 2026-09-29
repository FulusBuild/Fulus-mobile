-- Customer repayment mutation contract tests.
-- Executed after a clean local Supabase migration reset.
-- Disposable rows are rolled back and never reach production.

begin;

create temporary table _repayment_test_ids (
  user_id uuid not null,
  business_id uuid not null,
  role_id uuid not null,
  customer_id uuid not null,
  device_id uuid not null
) on commit drop;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at
)
values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'repayment-regression@example.test',
  'x',
  now()
);

insert into public.businesses (name)
values ('Customer Repayment Regression Business');

insert into public.roles (business_id, name, is_system)
select id, 'repayment-regression-role', false
from public.businesses
where name = 'Customer Repayment Regression Business';

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'credit.manage'
where r.name = 'repayment-regression-role';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select
  b.id,
  u.id,
  r.id,
  'active',
  now()
from public.businesses b
cross join auth.users u
join public.roles r
  on r.business_id = b.id
 and r.name = 'repayment-regression-role'
where b.name = 'Customer Repayment Regression Business'
  and u.email = 'repayment-regression@example.test';

insert into public.customers (
  business_id, name, credit_limit, outstanding_balance, is_active
)
select id, 'Repayment Regression Customer', 1000, 500, true
from public.businesses
where name = 'Customer Repayment Regression Business';

insert into public.devices (
  business_id, registered_by, device_client_id, device_name, platform, app_version, status, last_seen_at
)
select
  b.id,
  u.id,
  'repayment-regression-device',
  'Repayment Regression Device',
  'test',
  'test',
  'active',
  now()
from public.businesses b
cross join auth.users u
where b.name = 'Customer Repayment Regression Business'
  and u.email = 'repayment-regression@example.test';

insert into _repayment_test_ids
select
  u.id,
  b.id,
  r.id,
  c.id,
  d.id
from auth.users u
join public.businesses b
  on b.name = 'Customer Repayment Regression Business'
join public.roles r
  on r.business_id = b.id
 and r.name = 'repayment-regression-role'
join public.customers c
  on c.business_id = b.id
 and c.name = 'Repayment Regression Customer'
join public.devices d
  on d.business_id = b.id
 and d.registered_by = u.id
 and d.device_client_id = 'repayment-regression-device'
where u.email = 'repayment-regression@example.test';

-- Exercise the same authenticated-user claim binding used by the service wrapper.
set local role service_role;
select set_config(
  'request.jwt.claim.sub',
  (select user_id::text from _repayment_test_ids),
  true
);

do $$
declare
  ids _repayment_test_ids%rowtype;
  result jsonb;
  retry_result jsonb;
  balance numeric;
  ledger_count integer;
  customer_change_count integer;
  ledger_change_count integer;
begin
  select * into ids from _repayment_test_ids;

  -- The public service wrapper must reach the restored lower-level mutation.
  result := public.fulus_api_record_customer_repayment(
    ids.user_id,
    ids.business_id,
    ids.customer_id,
    125,
    'repayment-regression-operation',
    'cash',
    'Regression repayment',
    ids.device_id
  );

  if result->>'status' <> 'applied' then
    raise exception 'FAIL: first repayment was not applied: %', result;
  end if;

  if (result->>'new_balance')::numeric <> 375 then
    raise exception 'FAIL: authoritative response balance is %, expected 375', result->>'new_balance';
  end if;

  select outstanding_balance
  into balance
  from public.customers
  where id = ids.customer_id;

  if balance <> 375 then
    raise exception 'FAIL: customer balance is %, expected 375', balance;
  end if;

  select count(*)
  into ledger_count
  from public.customer_ledger_entries
  where business_id = ids.business_id
    and customer_id = ids.customer_id
    and operation_id = 'repayment-regression-operation'
    and entry_type = 'repayment';

  if ledger_count <> 1 then
    raise exception 'FAIL: expected exactly one repayment ledger entry, got %', ledger_count;
  end if;

  select count(*)
  into ledger_change_count
  from public.sync_changes
  where business_id = ids.business_id
    and entity_type = 'customer_ledger'
    and entity_id = (
      select id
      from public.customer_ledger_entries
      where business_id = ids.business_id
        and customer_id = ids.customer_id
        and operation_id = 'repayment-regression-operation'
        and entry_type = 'repayment'
    );

  if ledger_change_count <> 1 then
    raise exception 'FAIL: expected one canonical customer_ledger change, got %', ledger_change_count;
  end if;

  select count(*)
  into customer_change_count
  from public.sync_changes
  where business_id = ids.business_id
    and entity_type = 'customer'
    and entity_id = ids.customer_id
    and operation = 'upsert';

  if customer_change_count <> 1 then
    raise exception 'FAIL: expected one authoritative customer balance change, got %', customer_change_count;
  end if;

  -- Same operation id must be idempotent through the wrapper.
  retry_result := public.fulus_api_record_customer_repayment(
    ids.user_id,
    ids.business_id,
    ids.customer_id,
    125,
    'repayment-regression-operation',
    'cash',
    'Regression repayment',
    ids.device_id
  );

  if retry_result->>'status' <> 'applied' then
    raise exception 'FAIL: wrapper idempotent retry returned unexpected result: %', retry_result;
  end if;

  select count(*)
  into ledger_count
  from public.customer_ledger_entries
  where business_id = ids.business_id
    and customer_id = ids.customer_id
    and operation_id = 'repayment-regression-operation'
    and entry_type = 'repayment';

  if ledger_count <> 1 then
    raise exception 'FAIL: idempotent retry created a second ledger entry';
  end if;

  select outstanding_balance
  into balance
  from public.customers
  where id = ids.customer_id;

  if balance <> 375 then
    raise exception 'FAIL: idempotent retry changed balance to %', balance;
  end if;

  -- A different request reusing the same operation id must be rejected.
  begin
    perform public.fulus_api_record_customer_repayment(
      ids.user_id,
      ids.business_id,
      ids.customer_id,
      100,
      'repayment-regression-operation',
      'cash',
      'Different request',
      ids.device_id
    );
    raise exception 'FAIL: operation id accepted a different request';
  exception
    when sqlstate 'P0009' then
      null;
  end;

  -- Over-repayment must be rejected without mutating the balance.
  begin
    perform public.fulus_api_record_customer_repayment(
      ids.user_id,
      ids.business_id,
      ids.customer_id,
      500,
      'repayment-regression-overpayment',
      'cash',
      null,
      ids.device_id
    );
    raise exception 'FAIL: over-repayment was accepted';
  exception
    when sqlstate '22023' then
      null;
  end;

  select outstanding_balance
  into balance
  from public.customers
  where id = ids.customer_id;

  if balance <> 375 then
    raise exception 'FAIL: rejected over-repayment mutated balance to %', balance;
  end if;
end
$$;

reset role;

select 'PASS: repayment wrapper reaches restored mutation; balance, ledger and canonical sync changes are correct; idempotency and rejection paths hold' as result;

rollback;
