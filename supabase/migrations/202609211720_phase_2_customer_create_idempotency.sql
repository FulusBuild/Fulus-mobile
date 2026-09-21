-- Phase 2 completion: customer.create must be replay-safe just like
-- every other durable sync mutation. The prior create_customer RPC predates
-- the outbox contract and had no operation ID; the service wrapper now carries
-- the same idempotency envelope used by customer.update.
create or replace function public.create_customer(
  target_business_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_credit_limit numeric,
  target_notes text,
  target_operation_id text,
  target_device_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid:=auth.uid();
  cid uuid;
  idem public.idempotency_keys%rowtype;
  response jsonb;
begin
  if actor is null then
    raise exception using errcode='42501',message='Authentication required';
  end if;
  if not public.has_permission(target_business_id,'customers.manage') then
    raise exception using errcode='42501',message='Customer management permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id and business_id=target_business_id and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name))=0 then
    raise exception using errcode='22023',message='Customer name required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id))=0 then
    raise exception using errcode='22023',message='Customer operation_id required';
  end if;

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,actor,target_operation_id,
    'customer.create',target_request_hash
  )
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id;

  if idem.operation_type <> 'customer.create'
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;

  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  insert into public.customers(
    business_id,name,phone,email,address,credit_limit,notes
  )
  values(
    target_business_id,trim(target_name),nullif(trim(target_phone),''),
    nullif(trim(target_email),''),nullif(trim(target_address),''),
    greatest(coalesce(target_credit_limit,0),0),
    nullif(trim(target_notes),'')
  )
  returning id into cid;

  perform public._fulus_append_change(
    target_business_id,'customer',cid,'upsert',
    (select to_jsonb(c) from public.customers c where c.id=cid)
  );

  response := jsonb_build_object(
    'data',jsonb_build_object(
      'status','applied',
      'customer_id',cid,
      'entity_id',cid,
      'server_authoritative',true
    )
  );

  update public.idempotency_keys
  set response_status=201,response_body=response,completed_at=now()
  where id=idem.id;

  return response;
end
$$;

create or replace function public.fulus_api_create_customer(
  target_user_id uuid, target_business_id uuid, target_name text,
  target_phone text, target_email text, target_address text,
  target_credit_limit numeric, target_notes text,
  target_device_id uuid, target_operation_id text, target_request_hash text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_customer(
    target_business_id,target_name,target_phone,target_email,target_address,
    target_credit_limit,target_notes,target_operation_id,target_device_id,
    target_request_hash
  );
end;
$$;

revoke all on function public.create_customer(
  uuid,text,text,text,text,numeric,text
) from public,anon,authenticated;

revoke all on function public.create_customer(
  uuid,text,text,text,text,numeric,text,text,uuid,text
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text,uuid,text,text
) from public,anon,authenticated;

grant execute on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text,uuid,text,text
) to service_role;
