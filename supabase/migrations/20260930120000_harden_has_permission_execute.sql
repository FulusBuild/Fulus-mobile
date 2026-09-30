-- Authorization helpers are server-internal. RLS policies and
-- SECURITY DEFINER service functions may invoke has_permission, but clients
-- must not be able to call the helper directly through the Data API.
revoke execute on function public.has_permission(uuid, text)
  from public, anon, authenticated, service_role;
