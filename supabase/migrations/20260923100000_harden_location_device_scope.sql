-- Make location idempotency explicitly device-scoped.
create or replace function public.fulus_api_create_location(
 target_user_id uuid,target_business_id uuid,target_device_id uuid,target_operation_id text,target_name text,target_code text,target_address text,target_timezone text,target_request_hash text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=target_request_hash;
 if not exists (
   select 1 from public.devices
   where id=target_device_id and business_id=target_business_id
     and status='active' and registered_by=target_user_id
 ) then
   raise exception using errcode='42501',message='Device is not registered or active';
 end if;
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'location.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.device_id is distinct from target_device_id
    or idem.user_id is distinct from target_user_id then
   raise exception using errcode='P0009',
     message='Operation id was already used from a different device or account';
 end if;
 if idem.operation_type<>'location.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.create_location(target_business_id,target_operation_id,target_name,target_code,target_address,target_timezone);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.fulus_api_create_location(uuid,uuid,uuid,text,text,text,text,text,text) to service_role;

revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text,text) from service_role;
revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from service_role;
revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.fulus_api_create_location(uuid,uuid,uuid,text,text,text,text,text,text) to service_role;
