-- Keep this helper non-public at the Data API boundary.
revoke execute on function public.has_permission(uuid, text)
  from public, anon, service_role;
