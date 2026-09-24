-- Reassert the complete catalog mutation contract after later actor/search-path hardening.
-- A previous hardening migration accidentally replaced the initial-stock-aware
-- cloud_catalog_mutate body with an older version. Keep actor binding, idempotency
-- scope checks, conflict checks, and atomic product stock seeding together.

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
set search_path = ''
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
  change_sequence bigint;
begin
  if target_operation_id is null or length(trim(target_operation_id))=0 then
    raise exception using errcode='22023',message='operation_id is required';
  end if;
  if target_entity not in ('products','categories','suppliers') then
    raise exception using errcode='22023',message='Unsupported catalog entity';
  end if;
  if target_operation not in ('upsert','delete') then
    raise exception using errcode='22023',message='Unsupported catalog operation';
  end if;
  if not public.user_has_permission(target_business_id,target_user_id,'catalog.manage') then
    raise exception using errcode='42501',message='Catalog permission required';
  end if;
  if not exists(
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
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

  select * into idem from public.idempotency_keys
  where business_id=target_business_id and key=target_operation_id
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
        update public.products set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(products) into entity_id,row_data;
      when 'categories' then
        update public.categories set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(categories) into entity_id,row_data;
      when 'suppliers' then
        update public.suppliers set deleted_at=now(),updated_at=now()
        where id=target_id and business_id=target_business_id
        returning id,to_jsonb(suppliers) into entity_id,row_data;
    end case;
    if entity_id is null then
      raise exception using errcode='P0002',message='Catalog item not found';
    end if;
    select max(sc.sequence) into change_sequence
    from public.sync_changes sc
    where sc.business_id=target_business_id
      and sc.entity_type=feed_entity
      and sc.entity_id=entity_id;

    result:=jsonb_build_object(
      'data',jsonb_build_object(
        'entity',target_entity,'item',row_data,'entity_id',entity_id,
        'sync_sequence',change_sequence,
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
        raise exception using errcode='22023',
          message='Initial stock location does not belong to this business';
      end if;

      insert into public.product_stock_levels(
        product_id,location_id,current_stock,updated_at
      )
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

    select max(sc.sequence) into change_sequence
    from public.sync_changes sc
    where sc.business_id=target_business_id
      and sc.entity_type=feed_entity
      and sc.entity_id=entity_id;

    result:=jsonb_build_object(
      'data',jsonb_build_object(
        'entity',target_entity,'item',row_data,'entity_id',entity_id,
        'sync_sequence',change_sequence,
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

revoke execute on function public.cloud_catalog_mutate(
  uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text
) from PUBLIC,anon,authenticated;
grant execute on function public.cloud_catalog_mutate(
  uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text
) to service_role;
