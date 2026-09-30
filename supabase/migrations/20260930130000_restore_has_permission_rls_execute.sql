-- has_permission is a SECURITY DEFINER authorization helper used directly
-- by RLS policies. Authenticated execution is therefore required for those
-- policies to evaluate; do not remove it merely to silence the advisor.
revoke execute on function public.has_permission(uuid, text)
  from public, anon, service_role;
grant execute on function public.has_permission(uuid, text)
  to authenticated;
