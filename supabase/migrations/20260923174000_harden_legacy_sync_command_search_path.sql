-- The legacy sync_operation command remains service-role-only, but its
-- SECURITY DEFINER function should not retain a mutable schema search path.
alter function public.accept_sync_operation(
  uuid, uuid, uuid, text, text, text, text
) set search_path = '';
