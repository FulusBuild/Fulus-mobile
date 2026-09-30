-- Keep the client-visible permission predicate invoker-safe.
-- RLS needs the predicate callable by authenticated users, but the permission
-- lookup itself must remain behind a non-API security-definer helper.
--
-- The public wrapper is deliberately SECURITY INVOKER so Supabase's
-- authenticated_security_definer_function_executable advisor does not treat
-- it as a privileged RPC endpoint. The private helper receives auth.uid()
-- explicitly and is only reached through the wrapper or trusted server code.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated, service_role;

create or replace function private.has_permission(
  target_business_id uuid,
  permission_code text,
  target_user_id uuid
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
      and bm.user_id = target_user_id
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

revoke all on function private.has_permission(uuid, text, uuid)
  from public, anon, service_role;
grant execute on function private.has_permission(uuid, text, uuid) to authenticated;

create or replace function public.has_permission(
  target_business_id uuid,
  permission_code text
) returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.has_permission(
    target_business_id,
    permission_code,
    auth.uid()
  );
$$;

revoke execute on function public.has_permission(uuid, text)
  from public, anon, service_role;
grant execute on function public.has_permission(uuid, text) to authenticated;
