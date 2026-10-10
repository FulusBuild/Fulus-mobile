-- Ensure employee restore preserves location-attributable ledger history for
-- legacy shared/unassigned customers without exposing another location's ledger.
begin;

create temporary table _employee_ledger_scope_ids (
  worker_id uuid not null,
  business_id uuid not null,
  location_a_id uuid not null,
  location_b_id uuid not null,
  customer_id uuid not null,
  sale_a_id uuid not null,
  sale_b_id uuid not null
) on commit drop;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at)
values (
  gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'ledger-scope-worker@example.test', 'x', now()
);

insert into public.businesses (name)
values ('Employee Ledger Scope Business');

insert into public.roles (business_id, name, is_system)
select id, 'cashier', false
from public.businesses
where name = 'Employee Ledger Scope Business';

insert into public.locations (business_id, name, code, status)
select id, 'Ledger Scope A', 'LEDGER-A', 'active'
from public.businesses
where name = 'Employee Ledger Scope Business'
union all
select id, 'Ledger Scope B', 'LEDGER-B', 'active'
from public.businesses
where name = 'Employee Ledger Scope Business';

insert into _employee_ledger_scope_ids
select
  (select id from auth.users where email = 'ledger-scope-worker@example.test'),
  b.id,
  (select id from public.locations where business_id = b.id and code = 'LEDGER-A'),
  (select id from public.locations where business_id = b.id and code = 'LEDGER-B'),
  gen_random_uuid(),
  gen_random_uuid(),
  gen_random_uuid()
from public.businesses b
where b.name = 'Employee Ledger Scope Business';

insert into public.business_memberships (id, business_id, user_id, role_id, status, joined_at)
select gen_random_uuid(), t.business_id, t.worker_id, r.id, 'active', now()
from _employee_ledger_scope_ids t
join public.roles r on r.business_id = t.business_id and r.name = 'cashier';

insert into public.location_memberships (business_id, location_id, user_id, status)
select business_id, location_a_id, worker_id, 'active'
from _employee_ledger_scope_ids;

insert into public.employees (
  id, business_id, client_reference, membership_id, auth_user_id,
  full_name, role, email, location_id, is_active
)
select
  gen_random_uuid(), t.business_id, 'ledger-scope-worker', bm.id, t.worker_id,
  'Ledger Scope Worker', 'cashier', 'ledger-scope-worker@example.test',
  t.location_a_id, true
from _employee_ledger_scope_ids t
join public.business_memberships bm
  on bm.business_id = t.business_id
 and bm.user_id = t.worker_id
 and bm.status = 'active';

-- Simulate historical rows created before ownership guards existed: one shared
-- customer has sales and ledger entries in both locations, but no safe owner.
insert into public.customers (
  id, business_id, location_id, name, credit_limit, outstanding_balance, is_active
)
select customer_id, business_id, null, 'Shared Legacy Customer', 1000, 100, true
from _employee_ledger_scope_ids;

insert into public.sales (
  id, business_id, location_id, customer_id, client_reference, invoice_number,
  subtotal, discount, tax, total, amount_paid
)
select sale_a_id, business_id, location_a_id, null::uuid,
       'ledger-scope-sale-a', 'LEDGER-SCOPE-A', 100, 0, 0, 100, 0
from _employee_ledger_scope_ids
union all
select sale_b_id, business_id, location_b_id, null::uuid,
       'ledger-scope-sale-b', 'LEDGER-SCOPE-B', 100, 0, 0, 100, 0
from _employee_ledger_scope_ids;

alter table public.sales disable trigger sales_customer_location_guard;
update public.sales s
set customer_id = t.customer_id
from _employee_ledger_scope_ids t
where s.id in (t.sale_a_id, t.sale_b_id);
alter table public.sales enable trigger sales_customer_location_guard;

alter table public.customer_ledger_entries disable trigger customer_ledger_location_guard;
insert into public.customer_ledger_entries (
  business_id, customer_id, sale_id, entry_type, amount, operation_id, note
)
select business_id, customer_id, sale_a_id, 'credit_sale', 100,
       'ledger-scope-entry-a', 'Location A historical credit'
from _employee_ledger_scope_ids
union all
select business_id, customer_id, sale_b_id, 'credit_sale', 100,
       'ledger-scope-entry-b', 'Location B historical credit'
from _employee_ledger_scope_ids;
alter table public.customer_ledger_entries enable trigger customer_ledger_location_guard;

do $$
declare
  snapshot jsonb;
begin
  snapshot := public.build_fulus_employee_restore_snapshot(
    (select business_id from _employee_ledger_scope_ids),
    (select worker_id from _employee_ledger_scope_ids)
  );

  if not (snapshot -> 'customers' @> jsonb_build_array(
    jsonb_build_object('name', 'Historical customer')
  )) then
    raise exception 'FAIL: local historical customer placeholder was omitted';
  end if;
  if not (snapshot -> 'customer_ledger_entries' @> jsonb_build_array(
    jsonb_build_object('operation_id', 'ledger-scope-entry-a')
  )) then
    raise exception 'FAIL: employee restore omitted ledger history tied to its location sale';
  end if;
  if snapshot -> 'customer_ledger_entries' @> jsonb_build_array(
    jsonb_build_object('operation_id', 'ledger-scope-entry-b')
  ) then
    raise exception 'FAIL: employee restore exposed another location ledger entry';
  end if;
end
$$;

select 'PASS: employee restore retains local historical ledger references without leaking other-location entries' as result;
rollback;
