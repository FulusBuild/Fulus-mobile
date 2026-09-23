-- Fix the device-scoped location API wrapper so it does not call the
-- legacy create_location() helper, which attempts a second idempotency insert
-- without device_id and is rejected by the global scope guard.

create or replace function public.fulus_api_create_location(
  target_user_id uuid,
  target_business_id uuid,
  target_device_id uuid,
  target_operation_id text,
  target_name text,
  target_code text,
  target_address text,
  target_timezone text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $func$
declare
  idem public.idempotency_keys%rowtype;
  existing public.locations%rowtype;
  location_id uuid;
  result jsonb;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);

  if target_operation_id is null or length(trim(target_operation_id))=0 then
    raise exception using errcode='22023',message='Operation ID required';
  end if;
  if target_name is null or length(trim(target_name))=0 then
    raise exception using errcode='22023',message='Location name required';
  end if;
  if not exists (
    select 1 from public.business_memberships bm
    where bm.business_id=target_business_id
      and bm.user_id=target_user_id
      and bm.status='active'
  ) then
    raise exception using errcode='42501',message='Business membership required';
  end if;
  if not public.has_permission(target_business_id,'locations.manage') then
    raise exception using errcode='42501',message='Location management permission required';
  end if;
  if not exists (
    select 1 from public.devices d
    where d.id=target_device_id
      and d.business_id=target_business_id
      and d.registered_by=target_user_id
      and d.status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  ) values (
    target_business_id,target_device_id,target_user_id,target_operation_id,
    'location.create',target_request_hash
  ) on conflict (business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'location.create'
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  select * into existing
  from public.locations
  where business_id=target_business_id
    and lower(name)=lower(trim(target_name))
  limit 1;

  if existing.id is not null then
    result:=jsonb_build_object(
      'status','already_applied',
      'location_id',existing.id,
      'server_authoritative',true
    );
  else
    insert into public.locations(
      business_id,name,code,address,timezone,status
    ) values (
      target_business_id,
      trim(target_name),
      nullif(trim(target_code),''),
      nullif(trim(target_address),''),
      coalesce(nullif(trim(target_timezone),''),'Africa/Lagos'),
      'active'
    ) returning id into location_id;

    result:=jsonb_build_object(
      'status','applied',
      'location_id',location_id,
      'server_authoritative',true
    );
  end if;

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$func$;

revoke execute on function public.fulus_api_create_location(
  uuid,uuid,uuid,text,text,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.fulus_api_create_location(
  uuid,uuid,uuid,text,text,text,text,text,text
) to service_role;
