-- Restore EXECUTE only for the current actor-bound RPC signatures used by
-- the fulus-api Edge Function. The legacy-overload lockdown migration
-- accidentally revoked these active signatures as well.

revoke execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) from public,anon,authenticated;
grant execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) to service_role;

revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text
) from public,anon,authenticated;
grant execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text
) to service_role;
