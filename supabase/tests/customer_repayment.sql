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

insert into public.locations (business_id, name, status)
select id, 'Repayment Regression Location', 'active'
from public.businesses
where name = 'Customer Repayment Regression Business';


insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'credit.manage'
where r.name = 'repayment-regression-role';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select b.id, u.id, r.id, 'active', now()
from public.businesses b
cross join auth.users u
join public.roles r on r.business_id = b.id and r.name = 'repayment-regression-role'
where b.name = 'Customer Repayment Regression Business'
  and u.email = 'repayment-regression@example.test';

insert into public.location_memberships (business_id, location_id, user_id, status)
select b.id, l.id, u.id, 'active'
from public.businesses b
join public.locations l on l.business_id = b.id and l.name = 'Repayment Regression Location'
cross join auth.users u
where b.name = 'Customer Repayment Regression Business'
  and u.email = 'repayment-regression@example.test';

insert into public.customers (business_id, location_id, name, credit_limit, outstanding_balance, is_active)
select b.id, l.id, 'Repayment Regression Customer', 1000, 500, true
from public.businesses b
join public.locations l on l.business_id = b.id and l.name = 'Repayment Regression Location'
where b.name = 'Customer Repayment Regression Business';

insert into public.devices (
  business_id, registered_by, device_client_id, device_name, platform, app_version, status, last_seen_at
)
select b.id, u.id, 'repayment-regression-device', 'Repayment Regression Device',
       'test', 'test', 'active', now()
from public.businesses b
cross join auth.users u
where b.name = 'Customer Repayment Regression Business'
  and u.email = 'repayment-regression@example.test';

insert into _repayment_test_ids
select u.id, b.id, r.id, c.id, d.id
from auth.users u
join public.businesses b on b.name = 'Customer Repayment Regression Business'
join public.roles r on r.business_id = b.id and r.name = 'repayment-regression-role'
join public.customers c on c.business_id = b.id and c.name = 'Repayment Regression Customer'
join public.devices d on d.business_id = b.id and d.registered_by = u.id
  and d.device_client_id = 'repayment-regression-device'
where u.email = 'repayment-regression@example.test';

grant select on _repayment_test_ids to service_role;

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
  ledger_amount numeric;
  customer_change_count integer;
  ledger_change_count integer;
begin
  select * into ids from _repayment_test_ids;

  result := public.fulus_api_record_customer_repayment(
    ids.user_id, ids.business_id, ids.customer_id, 125,
    'repayment-regression-operation', 'cash', 'Regression repayment', ids.device_id
  );

  if result->>'status' <> 'applied' then
    raise exception 'FAIL: first repayment was not applied: %', result;
  end if;

  if (result->>'new_balance')::numeric <> 375 then
    raise exception 'FAIL: authoritative response balance is %, expected 375', result->>'new_balance';
  end if;

  if coalesce((result->>'excess_amount')::numeric, -1) <> 0 then
    raise exception 'FAIL: ordinary repayment reported excess %, expected 0', result->>'excess_amount';
  end if;

  select outstanding_balance into balance from public.customers where id = ids.customer_id;
  if balance <> 375 then
    raise exception 'FAIL: customer balance is %, expected 375', balance;
  end if;

  select count(*), coalesce(max(amount), 0)
  into ledger_count, ledger_amount
  from public.customer_ledger_entries
  where business_id = ids.business_id
    and customer_id = ids.customer_id
    and operation_id = 'repayment-regression-operation'
    and entry_type = 'repayment';

  if ledger_count <> 1 or ledger_amount <> 125 then
    raise exception 'FAIL: ordinary repayment ledger is count %, amount %, expected 1 and 125',
      ledger_count, ledger_amount;
  end if;

  select count(*) into ledger_change_count
  from public.sync_changes
  where business_id = ids.business_id
    and entity_type = 'customer_ledger'
    and entity_id = (
      select id from public.customer_ledger_entries
      where business_id = ids.business_id and customer_id = ids.customer_id
        and operation_id = 'repayment-regression-operation' and entry_type = 'repayment'
    );

  if ledger_change_count <> 1 then
    raise exception 'FAIL: expected one canonical customer_ledger change, got %', ledger_change_count;
  end if;

  select count(*) into customer_change_count
  from public.sync_changes
  where business_id = ids.business_id and entity_type = 'customer'
    and entity_id = ids.customer_id and operation = 'upsert';

  if customer_change_count <> 1 then
    raise exception 'FAIL: expected one authoritative customer balance change, got %', customer_change_count;
  end if;

  retry_result := public.fulus_api_record_customer_repayment(
    ids.user_id, ids.business_id, ids.customer_id, 125,
    'repayment-regression-operation', 'cash', 'Regression repayment', ids.device_id
  );

  if retry_result->>'status' <> 'applied' then
    raise exception 'FAIL: wrapper idempotent retry returned unexpected result: %', retry_result;
  end if;

  select count(*) into ledger_count
  from public.customer_ledger_entries
  where business_id = ids.business_id and customer_id = ids.customer_id
    and operation_id = 'repayment-regression-operation' and entry_type = 'repayment';

  if ledger_count <> 1 then
    raise exception 'FAIL: idempotent retry created a second ledger entry';
  end if;

  select outstanding_balance into balance from public.customers where id = ids.customer_id;
  if balance <> 375 then
    raise exception 'FAIL: idempotent retry changed balance to %', balance;
  end if;

  begin
    perform public.fulus_api_record_customer_repayment(
      ids.user_id, ids.business_id, ids.customer_id, 100,
      'repayment-regression-operation', 'cash', 'Different request', ids.device_id
    );
    raise exception 'FAIL: operation id accepted a different request';
  exception when sqlstate 'P0009' then null;
  end;

  -- Product contract: over-repayment is applied, full tender is preserved in
  -- the ledger, balance is capped at zero, and excess is returned.
  result := public.fulus_api_record_customer_repayment(
    ids.user_id, ids.business_id, ids.customer_id, 500,
    'repayment-regression-overpayment', 'cash', null, ids.device_id
  );

  if result->>'status' <> 'applied' then
    raise exception 'FAIL: over-repayment was not applied: %', result;
  end if;

  if (result->>'new_balance')::numeric <> 0 then
    raise exception 'FAIL: over-repayment balance is %, expected 0', result->>'new_balance';
  end if;

  if (result->>'excess_amount')::numeric <> 125 then
    raise exception 'FAIL: over-repayment excess is %, expected 125', result->>'excess_amount';
  end if;

  select outstanding_balance into balance from public.customers where id = ids.customer_id;
  if balance <> 0 then
    raise exception 'FAIL: over-repayment mutated balance to %, expected 0', balance;
  end if;

  select count(*), coalesce(max(amount), 0)
  into ledger_count, ledger_amount
  from public.customer_ledger_entries
  where business_id = ids.business_id and customer_id = ids.customer_id
    and operation_id = 'repayment-regression-overpayment' and entry_type = 'repayment';

  if ledger_count <> 1 or ledger_amount <> 500 then
    raise exception 'FAIL: over-repayment ledger is count %, amount %, expected 1 and 500',
      ledger_count, ledger_amount;
  end if;
end
$$;

reset role;

select 'PASS: repayment wrapper reaches restored mutation; balance, ledger, canonical sync, idempotency and overpayment semantics are correct' as result;

rollback;
