-- The legacy-wrapper lockdown must never remove execution from the active
-- actor-bound service signatures. Reassert the public Cloud API boundary after
-- all legacy overload revocations.
grant execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text,uuid,text,text
) to service_role;

grant execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) to service_role;

grant execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text
) to service_role;

grant execute on function public.fulus_api_create_location(
  uuid,uuid,uuid,text,text,text,text,text,text
) to service_role;
