-- Close remaining legacy service-role wrapper overloads. Core cloud_* functions
-- remain executable by service_role because the current device-bound wrappers
-- call them internally; only obsolete fulus_api_* overloads are revoked.

revoke execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric
) from service_role;
revoke execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text
) from service_role;

revoke execute on function public.fulus_api_record_expense(
  uuid,uuid,uuid,numeric,text,text,text,uuid
) from service_role;

revoke execute on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamp with time zone,text,uuid
) from service_role;
