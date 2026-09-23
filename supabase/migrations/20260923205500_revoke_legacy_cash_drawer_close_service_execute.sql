-- The 8-argument cash-drawer close RPC predates base-cursor/OCC
-- hardening. It is no longer called by the current API wrapper, so it must
-- not remain callable by service_role as a privileged bypass.
revoke execute on function public.cloud_close_cash_drawer_shift(
  uuid, uuid, numeric, numeric, text, timestamptz, text, uuid
) from service_role, public, anon, authenticated;
