-- Local-only adversarial authorization regression tests.
-- Executed after a clean local Supabase migration reset.
-- Disposable rows are rolled back and never reach production.

begin;

create temporary table _authz_test_ids (
  owner_id uuid not null,
  worker_id uuid not null,
  business_id uuid not null,
  location_a_id uuid not null,
  location_b_id uuid not null
) on commit drop;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'authz-owner@example.test', 'x', now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'authz-worker@example.test', 'x', now());

insert into public.businesses (name)
values ('Authorization Regression Business');

insert into public.roles (business_id, name, is_system)
select id, 'owner', true from public.businesses
where name = 'Authorization Regression Business'
union all
select id, 'cashier', false from public.businesses
where name = 'Authorization Regression Business';

insert into public.locations (business_id, name, code, status)
select id, 'Location A', 'AUTH-A', 'active'
from public.businesses
where name = 'Authorization Regression Business'
union all
select id, 'Location B', 'AUTH-B', 'active'
from public.businesses
where name = 'Authorization Regression Business';

grant select on _authz_test_ids to authenticated;

grant execute on function public.require_location_access(uuid, uuid) to authenticated;

insert into _authz_test_ids
select
  (select id from auth.users where email = 'authz-owner@example.test'),
  (select id from auth.users where email = 'authz-worker@example.test'),
  b.id,
  (select id from public.locations where business_id = b.id and code = 'AUTH-A'),
  (select id from public.locations where business_id = b.id and code = 'AUTH-B')
from public.businesses b
where b.name = 'Authorization Regression Business';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select t.business_id, t.owner_id, r.id, 'active', now()
from _authz_test_ids t
join public.roles r on r.business_id = t.business_id and r.name = 'owner';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select t.business_id, t.worker_id, r.id, 'active', now()
from _authz_test_ids t
join public.roles r on r.business_id = t.business_id and r.name = 'cashier';

insert into public.location_memberships (business_id, location_id, user_id, status)
select business_id, location_a_id, worker_id, 'active'
from _authz_test_ids;

-- Give the non-admin cashier read/manage capabilities, but only membership
-- in Location A. RLS must still hide and refuse mutations to Location B.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'catalog.read', 'catalog.manage', 'customers.read', 'customers.manage'
)
where r.business_id = (select business_id from _authz_test_ids)
  and r.name = 'cashier'
on conflict do nothing;

insert into public.products (business_id, location_id, name, sku, cost_price, selling_price)
select business_id, location_a_id, 'Authorization Product A', 'AUTHZ-PRODUCT-A', 0, 100
from _authz_test_ids
union all
select business_id, location_b_id, 'Authorization Product B', 'AUTHZ-PRODUCT-B', 0, 100
from _authz_test_ids;

insert into public.customers (business_id, location_id, name)
select business_id, location_a_id, 'Authorization Customer A'
from _authz_test_ids
union all
select business_id, location_b_id, 'Authorization Customer B'
from _authz_test_ids;

insert into public.businesses (name)
values ('Authorization Other Business');

insert into public.roles (business_id, name, is_system)
select id, 'owner', true from public.businesses
where name = 'Authorization Other Business';

insert into public.locations (business_id, name, code, status)
select id, 'Other Business Location', 'AUTH-OTHER', 'active'
from public.businesses
where name = 'Authorization Other Business';

-- Deliberately grant UPDATE in this rollback-only test so RLS, not table
-- privileges alone, is what prevents cross-location writes.
grant update on public.products, public.customers to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', (select worker_id::text from _authz_test_ids), true);

do $$
begin
  perform public.require_location_access(
    (select business_id from _authz_test_ids),
    (select location_a_id from _authz_test_ids)
  );
end
$$;

do $$
begin
  begin
    perform public.require_location_access(
      (select business_id from _authz_test_ids),
      (select location_b_id from _authz_test_ids)
    );
    raise exception 'FAIL: non-admin worker accessed an unassigned same-business location';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'User is not authorized for this location' then raise; end if;
  end;
end
$$;

do $$
begin
  begin
    perform public.require_location_access(
      (select business_id from _authz_test_ids),
      gen_random_uuid()
    );
    raise exception 'FAIL: nonexistent location was accepted';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'Location is not available in this business' then raise; end if;
  end;
end
$$;

do $$
declare
  product_count integer;
  customer_count integer;
  changed_count integer;
begin
  select count(*) into product_count
  from public.products
  where sku in ('AUTHZ-PRODUCT-A', 'AUTHZ-PRODUCT-B');
  if product_count <> 1 or not exists (
    select 1 from public.products where sku = 'AUTHZ-PRODUCT-A'
  ) then
    raise exception 'FAIL: product RLS did not isolate Location A from Location B';
  end if;

  select count(*) into customer_count
  from public.customers
  where name in ('Authorization Customer A', 'Authorization Customer B');
  if customer_count <> 1 or not exists (
    select 1 from public.customers where name = 'Authorization Customer A'
  ) then
    raise exception 'FAIL: customer RLS did not isolate Location A from Location B';
  end if;

  update public.products set name = 'Unauthorized Product Mutation'
  where sku = 'AUTHZ-PRODUCT-B';
  get diagnostics changed_count = row_count;
  if changed_count <> 0 then
    raise exception 'FAIL: Location A worker mutated Location B product';
  end if;

  update public.customers set name = 'Unauthorized Customer Mutation'
  where name = 'Authorization Customer B';
  get diagnostics changed_count = row_count;
  if changed_count <> 0 then
    raise exception 'FAIL: Location A worker mutated Location B customer';
  end if;
end
$$;
select set_config('request.jwt.claim.sub', (select owner_id::text from _authz_test_ids), true);

do $$
begin
  perform public.require_location_access(
    (select business_id from _authz_test_ids),
    (select location_b_id from _authz_test_ids)
  );
end
$$;

reset role;

-- The trigger must protect ownership even from privileged direct table writes.
do $$
begin
  begin
    update public.products
    set location_id = (select location_b_id from _authz_test_ids)
    where sku = 'AUTHZ-PRODUCT-A';
    raise exception 'FAIL: product location ownership transfer was accepted';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    update public.customers
    set location_id = (select location_b_id from _authz_test_ids)
    where name = 'Authorization Customer A';
    raise exception 'FAIL: customer location ownership transfer was accepted';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    update public.products
    set business_id = (select id from public.businesses where name = 'Authorization Other Business')
    where sku = 'AUTHZ-PRODUCT-A';
    raise exception 'FAIL: product business ownership transfer was accepted';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    update public.customers
    set business_id = (select id from public.businesses where name = 'Authorization Other Business')
    where name = 'Authorization Customer A';
    raise exception 'FAIL: customer business ownership transfer was accepted';
  exception
    when sqlstate '42501' then null;
  end;
end
$$;
select 'PASS: location access, product/customer RLS, and immutable tenant/location ownership contracts hold' as result;

rollback;
