-- Security cleanup: legacy overloaded cloud wrappers are no longer part of
-- the Fulus command contract. Keep them unavailable to client roles so the
-- Edge Function is the only externally reachable write path.
revoke all on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text
) from PUBLIC,anon,authenticated;

revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text
) from public,anon,authenticated;
