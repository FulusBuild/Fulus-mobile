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

-- The test owner needs the same explicit permission contract checked by the
-- employee mutation RPC; ownership review itself remains owner/admin-gated.
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'employees.manage'
where r.business_id = (
  select id from public.businesses where name = 'Authorization Regression Business'
)
and r.name = 'owner'
on conflict (role_id, permission_id) do nothing;

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

insert into public.devices (
  business_id, registered_by, device_client_id, device_name,
  platform, app_version, status, last_seen_at
)
select business_id, owner_id, 'ownership-review-device', 'Ownership Review Test',
       'test', '1', 'active', now()
from _authz_test_ids;

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

-- Legacy rows stay unassigned until an administrator makes an explicit choice.
insert into public.products (business_id, location_id, name, sku, cost_price, selling_price)
select business_id, null, 'Legacy Review Product', 'AUTHZ-LEGACY-PRODUCT', 0, 100
from _authz_test_ids;

insert into public.customers (business_id, location_id, name)
select business_id, null, 'Legacy Review Customer'
from _authz_test_ids;

insert into public.location_ownership_review
  (business_id, entity_type, entity_id, candidate_location_ids, classification, reason)
select t.business_id, 'product', p.id, array[t.location_a_id, t.location_b_id], 'ambiguous', 'test product'
from _authz_test_ids t join public.products p on p.business_id = t.business_id and p.sku = 'AUTHZ-LEGACY-PRODUCT'
union all
select t.business_id, 'customer', c.id, '{}'::uuid[], 'unassigned', 'test customer'
from _authz_test_ids t join public.customers c on c.business_id = t.business_id and c.name = 'Legacy Review Customer';

-- Legacy employee roster rows without location ownership must be reviewable,
-- not silently hidden from every location-filtered roster.
insert into public.employees(
  business_id, client_reference, auth_user_id, full_name, role, location_id, is_active
)
select t.business_id, 'AUTHZ-LEGACY-EMPLOYEE', t.worker_id,
       'Legacy Employee', 'cashier', null, true
from _authz_test_ids t;

insert into public.businesses (name)
values ('Authorization Other Business');

insert into public.roles (business_id, name, is_system)
select id, 'owner', true from public.businesses
where name = 'Authorization Other Business';

insert into public.locations (business_id, name, code, status)
select id, 'Other Business Location', 'AUTH-OTHER', 'active'
from public.businesses
where name = 'Authorization Other Business';

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

-- Direct table access remains intentionally unavailable to authenticated
-- clients; catalog/customer reads and writes go through the location-validating
-- Fulus API. The database-level ownership triggers below are still exercised
-- with the migration/test owner to prove they cannot be bypassed by privileged
-- direct writes.

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

-- Resolution is denied to a non-admin, rejects cross-business locations,
-- and atomically assigns only unresolved records while recording the reviewer.
do $ownership_review$ 
declare
  v_business uuid := (select business_id from _authz_test_ids);
  v_owner uuid := (select owner_id from _authz_test_ids);
  v_worker uuid := (select worker_id from _authz_test_ids);
  v_location_a uuid := (select location_a_id from _authz_test_ids);
  v_review uuid := (
    select lor.id from public.location_ownership_review lor
    join public.products p on p.id = lor.entity_id
    where lor.entity_type = 'product' and p.sku = 'AUTHZ-LEGACY-PRODUCT'
  );
  v_product uuid := (select id from public.products where sku = 'AUTHZ-LEGACY-PRODUCT');
  v_customer_review uuid := (
    select lor.id from public.location_ownership_review lor
    join public.customers c on c.id = lor.entity_id
    where lor.entity_type = 'customer' and c.name = 'Legacy Review Customer'
  );
  v_customer uuid := (select id from public.customers where name = 'Legacy Review Customer');
  v_employee_review uuid := (
    select lor.id from public.location_ownership_review lor
    join public.employees e on e.id = lor.entity_id
    where lor.entity_type = 'employee'
      and e.client_reference = 'AUTHZ-LEGACY-EMPLOYEE'
  );
  v_employee uuid := (
    select id from public.employees where client_reference = 'AUTHZ-LEGACY-EMPLOYEE'
  );
  v_device_id uuid := (
    select id from public.devices where device_client_id = 'ownership-review-device'
  );
  v_location_b uuid := (select location_b_id from _authz_test_ids);
  v_other_location uuid := (
    select l.id from public.locations l
    join public.businesses b on b.id = l.business_id
    where b.name = 'Authorization Other Business' and l.code = 'AUTH-OTHER'
  );
  v_result jsonb;
begin
  begin
    perform public.fulus_api_resolve_location_ownership(v_worker, v_business, v_review, v_location_a);
    raise exception 'FAIL: non-admin resolved legacy ownership';
  exception when sqlstate '42501' then null;
  end;

  begin
    perform public.fulus_api_resolve_location_ownership(v_owner, v_business, v_review, v_other_location);
    raise exception 'FAIL: cross-business location was accepted';
  exception when sqlstate '23503' then null;
  end;

  v_result := public.fulus_api_resolve_location_ownership(v_owner, v_business, v_review, v_location_a);
  if (select location_id from public.products where id = v_product) is distinct from v_location_a then
    raise exception 'FAIL: explicit product location was not assigned';
  end if;
  if not exists (
    select 1 from public.location_ownership_review
    where id = v_review and reviewed_at is not null and reviewed_by = v_owner
  ) then
    raise exception 'FAIL: review resolution was not recorded';
  end if;
  if v_result->>'location_id' is distinct from v_location_a::text then
    raise exception 'FAIL: resolution result does not report the selected location';
  end if;

  -- Customer resolution follows the same explicit, immutable ownership path.
  v_result := public.fulus_api_resolve_location_ownership(
    v_owner, v_business, v_customer_review, v_location_a
  );
  if (select location_id from public.customers where id = v_customer)
      is distinct from v_location_a then
    raise exception 'FAIL: explicit customer location was not assigned';
  end if;
  if not exists (
    select 1 from public.location_ownership_review
    where id = v_customer_review and reviewed_at is not null and reviewed_by = v_owner
  ) then
    raise exception 'FAIL: customer review resolution was not recorded';
  end if;
  if v_result->>'entity_type' is distinct from 'customer'
     or v_result->>'entity_id' is distinct from v_customer::text then
    raise exception 'FAIL: customer resolution result identifies the wrong entity';
  end if;

  -- A legacy API create without location is retained as unassigned, but it
  -- must automatically enter the owner/admin review queue and gain no location access.
  perform public.fulus_api_mutate_employee(
    target_business_id => v_business,
    target_user_id => v_owner,
    target_device_id => v_device_id,
    target_operation_id => 'ownership-review-null-create',
    target_operation => 'create',
    target_client_reference => 'AUTHZ-API-UNASSIGNED',
    target_full_name => 'API Unassigned Employee',
    target_role => 'cashier',
    target_location_id => null,
    target_is_active => true,
    target_request_hash => 'ownership-review-null-create-hash'
  );
  if not exists (
    select 1 from public.employees e
    join public.location_ownership_review lor
      on lor.entity_type = 'employee' and lor.entity_id = e.id
    where e.client_reference = 'AUTHZ-API-UNASSIGNED'
      and e.location_id is null and lor.reviewed_at is null
  ) then
    raise exception 'FAIL: API-created unassigned employee was not queued for ownership review';
  end if;

  -- Resolving an employee must assign the roster row, synchronize its active
  -- location membership, and publish the canonical employee change.
  v_result := public.fulus_api_resolve_location_ownership(
    v_owner, v_business, v_employee_review, v_location_b
  );
  if (select location_id from public.employees where id = v_employee)
      is distinct from v_location_b then
    raise exception 'FAIL: explicit employee location was not assigned';
  end if;
  if not exists (
    select 1 from public.location_ownership_review
    where id = v_employee_review and reviewed_at is not null and reviewed_by = v_owner
  ) then
    raise exception 'FAIL: employee review resolution was not recorded';
  end if;
  if v_result->>'entity_type' is distinct from 'employee'
     or v_result->>'entity_id' is distinct from v_employee::text then
    raise exception 'FAIL: employee resolution result identifies the wrong entity';
  end if;
  if not exists (
    select 1 from public.location_memberships
    where business_id = v_business and user_id = v_worker
      and location_id = v_location_b and status = 'active'
  ) then
    raise exception 'FAIL: employee resolution did not align active location membership';
  end if;
  if exists (
    select 1 from public.location_memberships
    where business_id = v_business and user_id = v_worker
      and location_id = (select location_a_id from _authz_test_ids)
      and status = 'active'
  ) then
    raise exception 'FAIL: employee resolution left an active membership at the previous location';
  end if;
  if not exists (
    select 1 from public.sync_changes
    where business_id = v_business and entity_type = 'employee'
      and entity_id = v_employee
  ) then
    raise exception 'FAIL: employee ownership resolution did not publish a sync change';
  end if;

  -- The normal roster mutation RPC must not transfer a resolved employee to
  -- another location; that would bypass the explicit ownership/transfer flow.
  begin
    perform public.fulus_api_mutate_employee(
      target_business_id => v_business,
      target_user_id => v_owner,
      target_device_id => v_device_id,
      target_operation_id => 'ownership-review-transfer-attempt',
      target_operation => 'update',
      target_employee_id => v_employee,
      target_full_name => 'Legacy Employee',
      target_role => 'cashier',
      target_location_id => (select location_a_id from _authz_test_ids),
      target_is_active => true,
      target_request_hash => 'ownership-review-transfer-hash'
    );
    raise exception 'FAIL: employee location transfer bypassed ownership review';
  exception when sqlstate '42501' then null;
  end;

  -- A resolved review cannot be replayed to transfer ownership again.
  begin
    perform public.fulus_api_resolve_location_ownership(
      v_owner, v_business, v_review,
      (select location_b_id from _authz_test_ids)
    );
    raise exception 'FAIL: an already-resolved ownership review was replayed';
  exception when sqlstate 'P0002' then null;
  end;
end
$ownership_review$;

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
