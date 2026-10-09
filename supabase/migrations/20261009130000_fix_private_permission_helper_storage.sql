-- Fix product-image Storage RLS authorization without exposing an arbitrary-user
-- permission oracle to authenticated clients.
--
-- The previous public.has_permission SECURITY INVOKER wrapper called a private
-- helper while authenticated had no USAGE on schema private, so Storage INSERT
-- policies failed with SQLSTATE 42501 ("permission denied for schema private").
--
-- Grant schema usage, but only expose a self-scoped helper. The new helper
-- obtains the caller from auth.uid() itself; authenticated clients must not be
-- able to call the legacy three-argument helper with an arbitrary target user.

create or replace function private.has_permission(
  target_business_id uuid,
  permission_code text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and (
        r.name = 'owner'
        or (
          bm.permissions_overridden
          and exists (
            select 1
            from public.business_member_permissions mp
            join public.permissions p on p.id = mp.permission_id
            where mp.business_id = bm.business_id
              and mp.user_id = bm.user_id
              and p.code = permission_code
          )
        )
        or (
          not bm.permissions_overridden
          and exists (
            select 1
            from public.role_permissions rp
            join public.permissions p on p.id = rp.permission_id
            where rp.role_id = bm.role_id
              and p.code = permission_code
          )
        )
      )
  );
$$;

revoke all on schema private from public, anon, authenticated, service_role;
grant usage on schema private to authenticated;

revoke all on function private.has_permission(uuid, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.has_permission(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function private.has_permission(uuid, text) to authenticated;

-- Keep the public RLS predicate invoker-safe. The called helper is self-scoped
-- and is the only private function authenticated clients may execute.
create or replace function public.has_permission(
  target_business_id uuid,
  permission_code text
) returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.has_permission(target_business_id, permission_code);
$$;

revoke execute on function public.has_permission(uuid, text)
  from public, anon, service_role;
grant execute on function public.has_permission(uuid, text) to authenticated;
