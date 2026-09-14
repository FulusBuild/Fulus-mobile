-- Restore snapshots are called through the authenticated Edge Function.
-- They must not be directly callable through PostgREST by public roles.
revoke execute on function public.build_fulus_restore_snapshot(uuid, uuid)
from public, anon, authenticated;
