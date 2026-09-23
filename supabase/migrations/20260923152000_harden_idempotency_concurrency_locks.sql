-- Harden idempotency reads against concurrent duplicate submissions.
-- The unique key prevents duplicate idempotency rows, but the existing row
-- must also be locked before checking completed_at and performing a mutation.

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
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare actor uuid:=auth.uid(); cid uuid; idem public.idempotency_keys%rowtype; response jsonb;
begin
  if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
  if not public.has_permission(target_business_id,'customers.manage') then raise exception using errcode='42501',message='Customer management permission required'; end if;
  if not exists (select 1 from public.devices where id=target_device_id and business_id=target_business_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
  if target_name is null or length(trim(target_name))=0 then raise exception using errcode='22023',message='Customer name required'; end if;
  if target_operation_id is null or length(trim(target_operation_id))=0 then raise exception using errcode='22023',message='Customer operation_id required'; end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,actor,target_operation_id,'customer.create',target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id or idem.user_id is distinct from actor then
    raise exception using errcode='P0009',message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'customer.create' or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;

  insert into public.customers(business_id,name,phone,email,address,credit_limit,notes)
  values(target_business_id,trim(target_name),nullif(trim(target_phone),''),nullif(trim(target_email),''),nullif(trim(target_address),''),greatest(coalesce(target_credit_limit,0),0),nullif(trim(target_notes),''))
  returning id into cid;

  perform public._fulus_append_change(target_business_id,'customer',cid,'upsert',(select to_jsonb(c) from public.customers c where c.id=cid));

  response:=jsonb_build_object('data',jsonb_build_object('status','applied','customer_id',cid,'entity_id',cid,'server_authoritative',true));
  update public.idempotency_keys set response_status=201,response_body=response,completed_at=now() where id=idem.id;
  return response;
end
$function$;

create or replace function public.fulus_api_create_expense_category(
  target_user_id uuid,target_business_id uuid,target_device_id uuid,target_operation_id text,target_name text,target_request_hash text
)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
declare idem public.idempotency_keys%rowtype; row_data public.expense_categories%rowtype; response jsonb;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  if not public.has_permission(target_business_id,'finance.manage') then raise exception using errcode='42501',message='Finance permission required'; end if;
  if not exists (select 1 from public.devices where id=target_device_id and business_id=target_business_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
  if target_name is null or length(trim(target_name))=0 then raise exception using errcode='22023',message='Expense category name required'; end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,'expense_category.create',target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'expense_category.create' or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;

  insert into public.expense_categories(business_id,name)
  values(target_business_id,trim(target_name))
  returning * into row_data;

  perform public._fulus_append_change(target_business_id,'expense_category',row_data.id,'upsert',to_jsonb(row_data));

  response:=jsonb_build_object('data',jsonb_build_object('entity_id',row_data.id,'status','applied','server_authoritative',true));
  update public.idempotency_keys set response_status=201,response_body=response,completed_at=now() where id=idem.id;
  return response;
end;
$function$;

create or replace function public.accept_sync_operation(
  target_business_id uuid,target_device_id uuid,target_user_id uuid,target_operation_id text,target_operation_type text,target_client_reference text,target_request_hash text
)
returns jsonb language plpgsql security definer set search_path = 'public'
as $function$
declare existing_idem public.idempotency_keys%rowtype; new_operation_id uuid; response jsonb;
begin
  if not exists (select 1 from public.business_memberships where business_id=target_business_id and user_id=target_user_id and status='active') then
    return jsonb_build_object('status_code',403,'error',jsonb_build_object('code','FORBIDDEN','message','User is not an active member of this business'));
  end if;
  if not exists (select 1 from public.devices where id=target_device_id and business_id=target_business_id and status='active') then
    return jsonb_build_object('status_code',403,'error',jsonb_build_object('code','DEVICE_NOT_REGISTERED','message','Device is not registered or active'));
  end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,target_operation_type,target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into existing_idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if existing_idem.device_id is distinct from target_device_id or existing_idem.user_id is distinct from target_user_id then
    return jsonb_build_object('status_code',409,'error',jsonb_build_object('code','IDEMPOTENCY_CONFLICT','message','Operation id was already used from a different device or account'));
  end if;
  if existing_idem.operation_type<>target_operation_type or existing_idem.request_hash<>target_request_hash then
    return jsonb_build_object('status_code',409,'error',jsonb_build_object('code','IDEMPOTENCY_CONFLICT','message','Operation id was already used with a different request'));
  end if;
  if existing_idem.completed_at is not null and existing_idem.response_body is not null then
    return jsonb_build_object('status_code',coalesce(existing_idem.response_status,200),'response',existing_idem.response_body);
  end if;

  insert into public.sync_operations(business_id,device_id,user_id,operation_id,operation_type,client_reference,status)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,target_operation_type,target_client_reference,'received')
  on conflict (business_id,device_id,operation_id) do nothing
  returning id into new_operation_id;

  response:=jsonb_build_object('data',jsonb_build_object('accepted',true,'operation_id',target_operation_id,'server_operation_id',new_operation_id,'status','received','server_authoritative',true));
  update public.idempotency_keys set response_status=202,response_body=response,completed_at=now() where id=existing_idem.id;
  return jsonb_build_object('status_code',202,'response',response);
end;
$function$;