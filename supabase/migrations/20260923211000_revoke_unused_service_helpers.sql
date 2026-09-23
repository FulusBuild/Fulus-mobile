-- These SECURITY DEFINER helpers are no longer part of the service API surface.
-- Location creation now performs the complete operation inside
-- fulus_api_create_location, so the legacy create_location helper is unused.
-- revoke_device is likewise superseded by the explicit self-revoke wrapper and
-- has no current application caller. Keep both callable by their definer for
-- internal compatibility, but remove the service-role execution surface.
revoke execute on function public.create_location(
  uuid, text, text, text, text, text
) from service_role, public, anon, authenticated;

revoke execute on function public.revoke_device(
  uuid, uuid, uuid
) from service_role, public, anon, authenticated;
