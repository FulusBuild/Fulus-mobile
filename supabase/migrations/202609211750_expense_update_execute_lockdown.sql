revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,text
) from PUBLIC,anon,authenticated;
grant execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,text
) to service_role;