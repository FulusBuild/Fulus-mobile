-- Production drift remediation: the original legacy-wrapper lockdown migration
-- is present in the repository but was not recorded in this production project's
-- migration history. Reassert the least-privilege boundary explicitly so legacy
-- service-role overloads cannot bypass the current device/request-hash contract.

revoke execute on function public.create_customer(
  uuid,text,text,text,text,numeric
) from service_role;
revoke execute on function public.create_customer(
  uuid,text,text,text,text,numeric,text
) from service_role;
revoke execute on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,text
) from service_role;
revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamp with time zone,text
) from service_role;
revoke execute on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamp with time zone,text,text
) from service_role;
