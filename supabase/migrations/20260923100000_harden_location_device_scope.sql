-- Make location idempotency explicitly device-scoped rather than relying only on the Edge request hash.


revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text,text) from service_role;
revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from service_role;
revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.fulus_api_create_location(uuid,uuid,uuid,text,text,text,text,text,text) to service_role;
