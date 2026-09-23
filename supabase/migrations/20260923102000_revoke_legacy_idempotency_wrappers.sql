-- Legacy service-role overloads bypass the current device-bound Cloud API contract.
-- No current Edge Function call site uses these signatures. Keep only the
-- device/request-hash-aware wrappers executable by service_role.

revoke execute on function public.create_customer(
  uuid,text,text,text,text,numeric
) from service_role;
revoke execute on function public.create_customer(
  uuid,text,text,text,text,numeric,text
) from service_role;
revoke execute on function public.create_customer(
  uuid,text,text,text,text,numeric,text,text
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
