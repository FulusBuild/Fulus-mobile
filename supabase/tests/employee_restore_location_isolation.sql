-- Part 04 regression tests for the employee bootstrap isolation boundary.
-- Run after a clean Supabase migration reset. Everything is rolled back.

begin;

create temporary table _employee_restore_test_ids (
  owner_id uuid not null,
  worker_id uuid not null,
  business_id uuid not null,
  location_a_id uuid not null,
  location_b_id uuid not null,
  worker_employee_id uuid not null
) on commit drop;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'restore-owner@example.test', 'x', now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'restore-worker@example.test', 'x', now());

insert into public.businesses (name)
values ('Employee Restore Isolation Business');

insert into public.roles (business_id, name, is_system)
select id, 'owner', true
from public.businesses
where name = 'Employee Restore Isolation Business'
union all
select id, 'cashier', false
from public.businesses
where name = 'Employee Restore Isolation Business';

insert into public.locations (business_id, name, code, status)
select id, 'Restore Location A', 'RESTORE-A', 'active'
from public.businesses
where name = 'Employee Restore Isolation Business'
union all
select id, 'Restore Location B', 'RESTORE-B', 'active'
from public.businesses
where name = 'Employee Restore Isolation Business';

insert into _employee_restore_test_ids
select
  (select id from auth.users where email = 'restore-owner@example.test'),
  (select id from auth.users where email = 'restore-worker@example.test'),
  b.id,
  (select id from public.locations where business_id = b.id and code = 'RESTORE-A'),
  (select id from public.locations where business_id = b.id and code = 'RESTORE-B'),
  gen_random_uuid()
from public.businesses b
where b.name = 'Employee Restore Isolation Business';

insert into public.business_memberships (id, business_id, user_id, role_id, status, joined_at)
select
  gen_random_uuid(), t.business_id, t.owner_id, r.id, 'active', now()
from _employee_restore_test_ids t
join public.roles r on r.business_id = t.business_id and r.name = 'owner';

insert into public.business_memberships (id, business_id, user_id, role_id, status, joined_at)
select
  gen_random_uuid(), t.business_id, t.worker_id, r.id, 'active', now()
from _employee_restore_test_ids t
join public.roles r on r.business_id = t.business_id and r.name = 'cashier';

insert into public.location_memberships (business_id, location_id, user_id, status)
select business_id, location_a_id, worker_id, 'active'
from _employee_restore_test_ids;

insert into public.employees (
  id, business_id, client_reference, membership_id, auth_user_id,
  full_name, role, email, location_id, is_active
)
select
  t.worker_employee_id,
  t.business_id,
  'restore-worker',
  bm.id,
  t.worker_id,
  'Restore Worker',
  'cashier',
  'restore-worker@example.test',
  t.location_a_id,
  true
from _employee_restore_test_ids t
join public.business_memberships bm
  on bm.business_id = t.business_id
 and bm.user_id = t.worker_id
 and bm.status = 'active';

do $$
declare
  snapshot jsonb;
  locations jsonb;
begin
  snapshot := public.build_fulus_employee_restore_snapshot(
    (select business_id from _employee_restore_test_ids),
    (select worker_id from _employee_restore_test_ids)
  );

  locations := snapshot -> 'locations';

  if jsonb_array_length(locations) <> 1 then
    raise exception 'FAIL: employee restore returned % locations, expected exactly 1', jsonb_array_length(locations);
  end if;

  if locations -> 0 ->> 'id' <>
     (select location_a_id::text from _employee_restore_test_ids) then
    raise exception 'FAIL: employee restore returned the wrong location';
  end if;

  if locations @> jsonb_build_array(jsonb_build_object(
    'id', (select location_b_id::text from _employee_restore_test_ids)
  )) then
    raise exception 'FAIL: employee restore included an unassigned location';
  end if;

  if jsonb_array_length(snapshot -> 'employees') <> 1 then
    raise exception 'FAIL: employee restore returned more than the signed-in employee';
  end if;
end
$$;

do $$
begin
  begin
    perform public.build_fulus_employee_restore_snapshot(
      (select business_id from _employee_restore_test_ids),
      (select owner_id from _employee_restore_test_ids)
    );
    raise exception 'FAIL: owner was allowed through employee-only restore RPC';
  exception
    when sqlstate '42501' then
      null;
  end;
end
$$;

delete from public.location_memberships
where business_id = (select business_id from _employee_restore_test_ids)
  and user_id = (select worker_id from _employee_restore_test_ids);

do $$
begin
  begin
    perform public.build_fulus_employee_restore_snapshot(
      (select business_id from _employee_restore_test_ids),
      (select worker_id from _employee_restore_test_ids)
    );
    raise exception 'FAIL: employee without active location membership received a restore';
  exception
    when sqlstate '42501' then
      null;
  end;
end
$$;

select 'PASS: employee restore is restricted to the assigned active location and rejects admin/missing-location callers' as result;

rollback;
