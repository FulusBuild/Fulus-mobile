-- Phase 0 security hardening.
-- Keep authorization helpers server-internal; clients must use the Fulus API.
revoke execute on function public.can_manage_role_permission(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.has_permission(uuid, text) from public, anon, authenticated;
revoke execute on function public.is_business_admin(uuid) from public, anon, authenticated;
revoke execute on function public.is_business_member(uuid) from public, anon, authenticated;
revoke execute on function public.is_location_member(uuid) from public, anon, authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
