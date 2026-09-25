-- Local-only adversarial authorization regression tests.
-- This file is executed after a clean local Supabase migration reset.
-- It deliberately creates disposable auth/business/location rows and rolls
-- everything back at the end. It is never a production migration.

begin;

create temporary table _authz_test_ids (
  owner_id uuid,
  worker_id uuid,
  business_id uuid,
  location_a_id uuid,
  location_b_id uuid
) on commit drop;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'authz-owner@example.test', 'x', now()),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'authz-worker@example.test', 'x', now())
returning id
into _authz_test_ids(owner_id);

-- PostgreSQL cannot return two generated rows into two scalar targets, so
-- normalize the identities from the deterministic test emails.
update _authz_test_ids
set
  owner_id = (select id from auth.users where email = 'authz-owner@example.test'),
  worker_id = (select id from auth.users where email = 'authz-worker@example.test');

insert into public.businesses (id, name)
values (gen_random_uuid(), 'Authorization Regression Business')
returning id into _authz_test_ids.business_id;

insert into public.roles (business_id, name, is_system)
values
  ((select business_id from _authz_test_ids), 'owner', true),
  ((select business_id from _authz_test_ids), 'cashier', false);

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select
  t.business_id,
  t.owner_id,
  r.id,
  'active',
  now()
from _authz_test_ids t
join public.roles r
  on r.business_id = t.business_id
 and r.name = 'owner';

insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
select
  t.business_id,
  t.worker_id,
  r.id,
  'active',
  now()
from _authz_test_ids t
join public.roles r
  on r.business_id = t.business_id
 and r.name = 'cashier';

insert into public.locations (business_id, name, code, status)
select business_id, 'Location A', 'AUTH-A', 'active'
from _authz_test_ids
returning id into _authz_test_ids.location_a_id;

insert into public.locations (business_id, name, code, status)
select business_id, 'Location B', 'AUTH-B', 'active'
from _authz_test_ids
returning id into _authz_test_ids.location_b_id;

insert into public.location_memberships (business_id, location_id, user_id, status)
select t.business_id, t.location_a_id, t.worker_id, 'active'
from _authz_test_ids t;

-- Worker is explicitly not a member of Location B.

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  (select worker_id::text from _authz_test_ids),
  true
);

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
    raise exception 'FAIL: non-admin worker accessed an unassigned location';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'User is not authorized for this location' then
        raise;
      end if;
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
      if sqlerrm <> 'Location is not available in this business' then
        raise;
      end if;
  end;
end
$$;

select set_config(
  'request.jwt.claim.sub',
  (select owner_id::text from _authz_test_ids),
  true
);

do $$
begin
  perform public.require_location_access(
    (select business_id from _authz_test_ids),
    (select location_b_id from _authz_test_ids)
  );
end
$$;

reset role;

select 'PASS: non-admin location authorization blocks same-business unassigned location and owner/admin retains cross-location access' as result;

rollback;
