-- The mobile client reaches cash-drawer close through the privileged fulus-api Edge Function.
-- Direct PostgREST RPC execution must therefore not be exposed to public roles.
REVOKE EXECUTE ON FUNCTION public.cloud_close_cash_drawer_shift(
  uuid, uuid, numeric, numeric, text, timestamptz, text, uuid, bigint
) FROM PUBLIC, anon, authenticated;
