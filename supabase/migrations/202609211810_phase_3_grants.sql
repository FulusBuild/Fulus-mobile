grant execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) to service_role;
grant execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text
) to service_role;
grant execute on function public.cloud_catalog_mutate(
  uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text
) to service_role;