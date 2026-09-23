-- Bind actor identity to the registered device at every public service-role
-- wrapper that accepts an explicit user/device pair.

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
as $function$
declare
  actor uuid := auth.uid();
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
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=actor
      and status='active'
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

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from actor then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;

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
      'status','applied','customer_id',cid,'entity_id',cid,
      'server_authoritative',true
    )
  );

  update public.idempotency_keys
  set response_status=201,response_body=response,completed_at=now()
  where id=idem.id;

  return response;
end
$function$;

create or replace function public.fulus_api_create_expense_category(
  target_user_id uuid,
  target_business_id uuid,
  target_device_id uuid,
  target_operation_id text,
  target_name text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  row_data public.expense_categories%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  if not public.has_permission(target_business_id,'finance.manage') then
    raise exception using errcode='42501',message='Finance permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name))=0 then
    raise exception using errcode='22023',message='Expense category name required';
  end if;

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,target_operation_id,
    'expense_category.create',target_request_hash
  )
  on conflict (business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;
  if idem.operation_type <> 'expense_category.create'
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  insert into public.expense_categories(business_id,name)
  values(target_business_id,trim(target_name))
  returning * into row_data;

  perform public._fulus_append_change(
    target_business_id,'expense_category',row_data.id,'upsert',to_jsonb(row_data)
  );

  response := jsonb_build_object(
    'data',jsonb_build_object(
      'entity_id',row_data.id,'status','applied','server_authoritative',true
    )
  );
  update public.idempotency_keys
  set response_status=201,response_body=response,completed_at=now()
  where id=idem.id;
  return response;
end;
$function$;

create or replace function public.fulus_api_update_customer(
  target_user_id uuid,target_business_id uuid,target_device_id uuid,
  target_operation_id text,target_customer_id uuid,target_name text,
  target_phone text,target_email text,target_address text,target_notes text,
  target_credit_limit numeric,target_is_active boolean,target_base_cursor bigint,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  customer_row public.customers%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  if not public.has_permission(target_business_id,'customers.manage') then
    raise exception using errcode='42501',message='Customer management permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name))=0 then
    raise exception using errcode='22023',message='Customer name required';
  end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,'customer.update',target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id for update;

  if idem.operation_type <> 'customer.update' or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  if target_base_cursor is not null and exists (
    select 1 from public.sync_changes
    where business_id=target_business_id
      and entity_type='customer'
      and entity_id=target_customer_id
      and sequence > target_base_cursor
  ) then
    raise exception using errcode='P0008',
      message='SYNC_CONFLICT: Customer changed on another device after this edit was created';
  end if;

  update public.customers
  set name=trim(target_name),phone=nullif(trim(target_phone),''),
      email=nullif(trim(target_email),''),address=nullif(trim(target_address),''),
      notes=nullif(trim(target_notes),''),
      credit_limit=greatest(coalesce(target_credit_limit,0),0),
      is_active=coalesce(target_is_active,true),updated_at=now()
  where id=target_customer_id and business_id=target_business_id
  returning * into customer_row;

  if not found then
    raise exception using errcode='P0002',message='Customer not found';
  end if;

  perform public._fulus_append_change(
    target_business_id,'customer',customer_row.id,'upsert',to_jsonb(customer_row)
  );

  response := jsonb_build_object(
    'data',jsonb_build_object(
      'entity_id',customer_row.id,'customer_id',customer_row.id,
      'status','applied','server_authoritative',true
    )
  );
  update public.idempotency_keys
  set response_status=200,response_body=response,completed_at=now()
  where id=idem.id;
  return response;
end;
$function$;

create or replace function public.fulus_api_update_expense(
  target_user_id uuid,target_business_id uuid,target_device_id uuid,
  target_operation_id text,target_expense_id uuid,target_location_id uuid,
  target_amount numeric,target_category text,target_description text,
  target_expense_date timestamptz,target_payment_method text,
  target_base_cursor bigint,target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  idem public.idempotency_keys%rowtype;
  expense_row public.expenses%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  if not public.has_permission(target_business_id,'finance.manage') then
    raise exception using errcode='42501',message='Finance permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception using errcode='22023',message='Expense amount must be greater than zero';
  end if;
  if target_category is null or length(trim(target_category))=0 then
    raise exception using errcode='22023',message='Expense category required';
  end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,'expense.update',target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id for update;

  if idem.operation_type <> 'expense.update' or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  if target_base_cursor is not null and exists (
    select 1 from public.sync_changes
    where business_id=target_business_id
      and entity_type='expense'
      and entity_id=target_expense_id
      and sequence > target_base_cursor
  ) then
    raise exception using errcode='P0008',
      message='SYNC_CONFLICT: Expense changed on another device after this edit was created';
  end if;

  update public.expenses
  set location_id=target_location_id,amount=target_amount,
      category=trim(target_category),description=target_description,
      expense_date=target_expense_date,payment_method=target_payment_method
  where id=target_expense_id and business_id=target_business_id
  returning * into expense_row;

  if not found then
    raise exception using errcode='P0002',message='Expense not found';
  end if;

  update public.cash_ledger
  set location_id=target_location_id,amount=target_amount
  where business_id=target_business_id and reference_id=expense_row.id
    and entry_type='expense' and direction='out';

  perform public._fulus_append_change(
    target_business_id,'expense',expense_row.id,'upsert',to_jsonb(expense_row)
  );

  response := jsonb_build_object(
    'data',jsonb_build_object(
      'entity_id',expense_row.id,'expense_id',expense_row.id,
      'status','applied','server_authoritative',true
    )
  );
  update public.idempotency_keys
  set response_status=200,response_body=response,completed_at=now()
  where id=idem.id;
  return response;
end;
$function$;