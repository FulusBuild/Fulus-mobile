-- Cloud Sync V1 hardening: idempotency keys must never cross device/user scope.
-- Existing rows remain compatible; a reused operation ID from another device/user is rejected deterministically.

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

create or replace function public.fulus_api_update_customer(
  target_user_id uuid, target_business_id uuid, target_device_id uuid,
  target_operation_id text, target_customer_id uuid,
  target_name text, target_phone text, target_email text,
  target_address text, target_notes text, target_credit_limit numeric,
  target_is_active boolean, target_base_cursor bigint, target_request_hash text
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  idem public.idempotency_keys%rowtype;
  customer_row public.customers%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if not public.has_permission(target_business_id, 'customers.manage') then
    raise exception using errcode='42501', message='Customer management permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id and business_id=target_business_id and status='active'
  ) then
    raise exception using errcode='42501', message='Device is not registered or active';
  end if;
  if target_name is null or length(trim(target_name))=0 then
    raise exception using errcode='22023', message='Customer name required';
  end if;

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,target_user_id,target_operation_id,'customer.update',target_request_hash)
  on conflict (business_id,key) do nothing;

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;

  if idem.operation_type <> 'customer.update' or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009', message='Operation id was already used with a different request';
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
  set name=trim(target_name),
      phone=nullif(trim(target_phone),''),
      email=nullif(trim(target_email),''),
      address=nullif(trim(target_address),''),
      notes=nullif(trim(target_notes),''),
      credit_limit=greatest(coalesce(target_credit_limit,0),0),
      is_active=coalesce(target_is_active,true),
      updated_at=now()
  where id=target_customer_id and business_id=target_business_id
  returning * into customer_row;

  if not found then
    raise exception using errcode='P0002', message='Customer not found';
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
$$;

create or replace function public.fulus_api_update_expense(
  target_user_id uuid, target_business_id uuid, target_device_id uuid,
  target_operation_id text, target_expense_id uuid, target_location_id uuid,
  target_amount numeric, target_category text, target_description text,
  target_expense_date timestamptz, target_payment_method text,
  target_base_cursor bigint, target_request_hash text
)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  idem public.idempotency_keys%rowtype;
  expense_row public.expenses%rowtype;
  response jsonb;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if not public.has_permission(target_business_id,'finance.manage') then
    raise exception using errcode='42501',message='Finance permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id and business_id=target_business_id and status='active'
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
  where business_id=target_business_id and key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;

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
  set location_id=target_location_id,
      amount=target_amount,
      category=trim(target_category),
      description=target_description,
      expense_date=target_expense_date,
      payment_method=target_payment_method,
      updated_at=now()
  where id=target_expense_id and business_id=target_business_id
  returning * into expense_row;

  if not found then
    raise exception using errcode='P0002',message='Expense not found';
  end if;

  update public.cash_ledger
  set location_id=target_location_id, amount=target_amount
  where business_id=target_business_id
    and reference_id=expense_row.id
    and entry_type='expense'
    and direction='out';

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
$$;

create or replace function public.cloud_catalog_mutate(
  target_business_id uuid,
  target_user_id uuid,
  target_device_id uuid,
  target_operation_id text,
  target_entity text,
  target_operation text,
  target_id uuid,
  target_item jsonb,
  target_base_cursor bigint,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  idem public.idempotency_keys%rowtype;
  result jsonb;
  row_data jsonb;
  entity_id uuid;
  feed_entity text;
  initial_stock integer;
  initial_location_id uuid;
  initial_movement_id uuid;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);

  if target_operation_id is null or length(trim(target_operation_id))=0 then
    raise exception using errcode='22023',message='operation_id is required';
  end if;
  if target_entity not in ('products','categories','suppliers') then
    raise exception using errcode='22023',message='Unsupported catalog entity';
  end if;
  if target_operation not in ('upsert','delete') then
    raise exception using errcode='22023',message='Unsupported catalog operation';
  end if;
  if not exists (
    select 1 from public.business_memberships bm
    where bm.business_id=target_business_id
      and bm.user_id=target_user_id
      and bm.status='active'
  ) then
    raise exception using errcode='42501',message='Business membership required';
  end if;
  if not public.has_permission(target_business_id,'catalog.manage') then
    raise exception using errcode='42501',message='Catalog permission required';
  end if;
  if not exists (
    select 1 from public.devices d
    where d.id=target_device_id
      and d.business_id=target_business_id
      and d.status='active'
      and d.registered_by=target_user_id
  ) then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,target_operation_id,
    'catalog.'||target_entity||'.'||target_operation,target_request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys ik
  where ik.business_id=target_business_id
    and ik.key=target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id then
    raise exception using errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;

  if idem.operation_type <> 'catalog.'||target_entity||'.'||target_operation
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  feed_entity := case target_entity
    when 'products' then 'product'
    when 'categories' then 'category'
    when 'suppliers' then 'supplier'
  end;

  if target_id is not null and target_base_cursor is not null and exists (
    select 1
    from public.sync_changes sc
    where sc.business_id=target_business_id
      and sc.entity_type=feed_entity
      and sc.entity_id=target_id
      and sc.sequence > target_base_cursor
  ) then
    raise exception using errcode='P0008',
      message='SYNC_CONFLICT: '||initcap(feed_entity)||
        ' changed on another device after this edit was created';
  end if;

  if target_operation='delete' then
    if target_id is null then
      raise exception using errcode='22023',message='Catalog delete requires id';
    end if;
    case target_entity
      when 'products' then
        update public.products
        set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(products) into entity_id,row_data;
      when 'categories' then
        update public.categories
        set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(categories) into entity_id,row_data;
      when 'suppliers' then
        update public.suppliers
        set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(suppliers) into entity_id,row_data;
    end case;
    if entity_id is null then
      raise exception using errcode='P0002',message='Catalog item not found';
    end if;
    result:=jsonb_build_object(
      'data',jsonb_build_object(
        'entity',target_entity,'item',row_data,'entity_id',entity_id,
        'status','deleted','server_authoritative',true
      )
    );
  else
    if target_item is null or jsonb_typeof(target_item)<>'object' then
      raise exception using errcode='22023',message='Catalog item is required';
    end if;
    case target_entity
      when 'categories' then
        if target_id is null then
          insert into public.categories(business_id,name,description)
          values(target_business_id,trim(target_item->>'name'),
                 nullif(target_item->>'description',''))
          returning id,to_jsonb(categories) into entity_id,row_data;
        else
          update public.categories
          set name=trim(target_item->>'name'),
              description=nullif(target_item->>'description',''),
              updated_at=now()
          where id=target_id and business_id=target_business_id
          returning id,to_jsonb(categories) into entity_id,row_data;
        end if;
      when 'suppliers' then
        if target_id is null then
          insert into public.suppliers(business_id,name,phone,email,address)
          values(target_business_id,trim(target_item->>'name'),
                 target_item->>'phone',target_item->>'email',target_item->>'address')
          returning id,to_jsonb(suppliers) into entity_id,row_data;
        else
          update public.suppliers
          set name=trim(target_item->>'name'),
              phone=target_item->>'phone',
              email=target_item->>'email',
              address=target_item->>'address',
              updated_at=now()
          where id=target_id and business_id=target_business_id
          returning id,to_jsonb(suppliers) into entity_id,row_data;
        end if;
      when 'products' then
        if target_id is null then
          insert into public.products(
            business_id,name,sku,barcode,category_id,supplier_id,
            cost_price,selling_price,low_stock_threshold,is_active
          )
          values(
            target_business_id,trim(target_item->>'name'),target_item->>'sku',
            target_item->>'barcode',
            nullif(target_item->>'category_id','')::uuid,
            nullif(target_item->>'supplier_id','')::uuid,
            coalesce(nullif(target_item->>'cost_price','')::numeric,0),
            coalesce(nullif(target_item->>'selling_price','')::numeric,0),
            coalesce(nullif(target_item->>'low_stock_threshold','')::integer,0),
            coalesce((target_item->>'is_active')::boolean,true)
          )
          returning id,to_jsonb(products) into entity_id,row_data;
        else
          update public.products
          set name=trim(target_item->>'name'),
              sku=target_item->>'sku',
              barcode=target_item->>'barcode',
              category_id=nullif(target_item->>'category_id','')::uuid,
              supplier_id=nullif(target_item->>'supplier_id','')::uuid,
              cost_price=coalesce(nullif(target_item->>'cost_price','')::numeric,0),
              selling_price=coalesce(nullif(target_item->>'selling_price','')::numeric,0),
              low_stock_threshold=coalesce(nullif(target_item->>'low_stock_threshold','')::integer,0),
              is_active=coalesce((target_item->>'is_active')::boolean,true),
              updated_at=now()
          where id=target_id and business_id=target_business_id
          returning id,to_jsonb(products) into entity_id,row_data;
        end if;
    end case;

    if entity_id is null then
      raise exception using errcode='P0002',message='Catalog item not found';
    end if;

    -- Product creation must seed the authoritative stock ledger in the same
    -- transaction as the product row. The mobile client is local-first and
    -- sends the exact location plus initial quantity with the create command.
    if target_entity='products' and target_id is null then
      initial_stock := coalesce(nullif(target_item->>'initial_stock','')::integer,0);
      if initial_stock < 0 then
        raise exception using errcode='22023',message='Initial stock cannot be negative';
      end if;

      initial_location_id := nullif(target_item->>'location_id','')::uuid;
      if initial_location_id is null then
        raise exception using errcode='22023',message='Initial stock requires a location';
      end if;
      if not exists (
        select 1 from public.locations l
        where l.id=initial_location_id and l.business_id=target_business_id
      ) then
        raise exception using errcode='22023',message='Initial stock location does not belong to this business';
      end if;

      insert into public.product_stock_levels(product_id,location_id,current_stock,updated_at)
      values(entity_id,initial_location_id,initial_stock,now())
      on conflict(product_id,location_id) do update
        set current_stock=excluded.current_stock,updated_at=now();

      if initial_stock > 0 then
        insert into public.inventory_movements(
          business_id,product_id,location_id,quantity_delta,reason,
          operation_id,user_id,device_id
        )
        values(
          target_business_id,entity_id,initial_location_id,initial_stock,
          'Initial stock',target_operation_id||':initial-stock',
          target_user_id,target_device_id
        )
        on conflict(business_id,operation_id) do nothing
        returning id into initial_movement_id;

        if initial_movement_id is not null then
          perform public._fulus_append_change(
            target_business_id,'stock_movement',initial_movement_id,'upsert',
            jsonb_build_object(
              'id',initial_movement_id,
              'product_id',entity_id,
              'location_id',initial_location_id,
              'quantity_delta',initial_stock,
              'reason','Initial stock',
              'current_stock',initial_stock
            )
          );
        end if;
      end if;
    end if;

    result:=jsonb_build_object(
      'data',jsonb_build_object(
        'entity',target_entity,'item',row_data,'entity_id',entity_id,
        'status',case when target_id is null then 'created' else 'updated' end,
        'server_authoritative',true
      )
    );
  end if;

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$$;


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
as $
declare
  idem public.idempotency_keys%rowtype;
  result jsonb;
begin
  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501',
      message='Device is not registered or active';
  end if;

  insert into public.idempotency_keys(
    business_id,device_id,user_id,key,operation_type,request_hash
  )
  values(
    target_business_id,target_device_id,target_user_id,target_operation_id,
    'location.create',target_request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id=target_business_id
    and key=target_operation_id
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

  perform set_config('request.jwt.claim.sub',target_user_id::text,true);

  result := public.create_location(
    target_business_id,
    target_operation_id,
    target_name,
    target_code,
    target_address,
    target_timezone
  );

  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;

  return result;
end;
$;

revoke execute on function public.fulus_api_create_location(
  uuid,uuid,uuid,text,text,text,text,text,text
) from public,anon,authenticated;
grant execute on function public.fulus_api_create_location(
  uuid,uuid,uuid,text,text,text,text,text,text
) to service_role;

-- Legacy location wrapper signatures are no longer part of the Cloud API contract.
-- Keep them unavailable to client roles so only the device-bound wrapper is reachable
-- through the Edge Function.
revoke execute on function public.fulus_api_create_location(
  uuid,uuid,text,text,text,text,text,text
) from public,anon,authenticated;
revoke execute on function public.fulus_api_create_location(
  uuid,uuid,text,text,text,text,text
) from public,anon,authenticated;


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
