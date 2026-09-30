-- has_permission is invoked by RLS policies, so authenticated execution is
-- required for policy evaluation. Keep the helper unavailable to anon/public.
revoke execute on function public.has_permission(uuid, text)
  from public, anon, service_role;
grant execute on function public.has_permission(uuid, text) to authenticated;
