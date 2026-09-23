-- Lock down every obsolete overloaded service wrapper signature.
--
-- The Edge Function calls only the current actor-bound signatures. Older
-- overloads remained SECURITY DEFINER and service-role callable after later
-- contract migrations, which left an unnecessary privileged API surface.

revoke execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric
) from service_role;

revoke execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text
) from service_role;

revoke execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,text
) from service_role;

revoke execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,bigint,text
) from service_role;

revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text
) from service_role;

revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,text
) from service_role;

revoke execute on function public.fulus_api_create_location(
  uuid,uuid,text,text,text,text,text
) from service_role;

revoke execute on function public.fulus_api_create_location(
  uuid,uuid,text,text,text,text,text,text
) from service_role;
