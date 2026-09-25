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
select 'PASS: same-business non-admin is blocked from an unassigned location; owner/admin retains cross-location access' as result;

rollback;
