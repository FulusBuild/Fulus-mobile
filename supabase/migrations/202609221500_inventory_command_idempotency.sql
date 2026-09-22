-- Cloud Sync V1: make inventory command idempotency payload-sensitive.
--
-- Inventory commands previously keyed replay handling only by operation_id.
-- A retry with the same operation_id but a different quantity/reason could
-- therefore be accepted as an ordinary replay. Persist the request hash in
-- the shared business-scoped idempotency table, matching the catalog command
-- contract.
create or replace function public.apply_inventory_adjustment(
  target_business_id uuid,
  target_product_id uuid,
  target_location_id uuid,
  target_quantity_delta integer,
  target_reason text,
  target_operation_id text,
  target_device_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor uuid := auth.uid();
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
  old_stock integer;
  new_stock integer;
  movement_id uuid;
  existing_delta integer;
  existing_reason text;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='operation_id is required';
  end if;
  if target_quantity_delta = 0 then
    raise exception using errcode='22023', message='Quantity delta cannot be zero';
  end if;
  if not public.has_permission(target_business_id,'inventory.adjust') then
    raise exception using errcode='42501', message='Inventory adjustment permission required';
  end if;
  if target_device_id is not null and not exists(
    select 1 from public.devices d
    where d.id=target_device_id and d.business_id=target_business_id and d.status='active'
  ) then
    raise exception using errcode='42501', message='Device is not active for this business';
  end if;
  if not exists(
    select 1 from public.products p
    where p.id=target_product_id and p.business_id=target_business_id and p.deleted_at is null
  ) then
    raise exception using errcode='22023', message='Product does not belong to business';
  end if;
  if not exists(
    select 1 from public.locations l
    where l.id=target_location_id and l.business_id=target_business_id
  ) then
    raise exception using errcode='22023', message='Location does not belong to business';
  end if;

  request_hash := md5(jsonb_build_object(
    'business_id', target_business_id,
    'product_id', target_product_id,
    'location_id', target_location_id,
    'quantity_delta', target_quantity_delta,
    'reason', trim(target_reason),
    'device_id', target_device_id
  )::text);

  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  )
  values(
    target_business_id, target_device_id, actor, target_operation_id,
    'inventory.adjust', request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys ik
  where ik.business_id=target_business_id and ik.key=target_operation_id
  for update;

  if idem.operation_type <> 'inventory.adjust' or idem.request_hash <> request_hash then
    raise exception using errcode='P0009', message='Operation id was already used with a different request';
  end if;

  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  insert into public.inventory_movements(
    business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id
  )
  values(
    target_business_id,target_product_id,target_location_id,target_quantity_delta,
    trim(target_reason),target_operation_id,actor,target_device_id
  )
  on conflict (business_id,operation_id) do nothing
  returning id into movement_id;

  if movement_id is null then
    select im.id, im.quantity_delta, im.reason
      into movement_id, existing_delta, existing_reason
    from public.inventory_movements im
    where im.business_id=target_business_id and im.operation_id=target_operation_id
    for update;

    if existing_delta <> target_quantity_delta
       or coalesce(existing_reason,'') <> coalesce(trim(target_reason),'') then
      raise exception using errcode='P0009', message='Operation id was already used with a different request';
    end if;

    select current_stock into new_stock
    from public.product_stock_levels
    where product_id=target_product_id and location_id=target_location_id;

    result := jsonb_build_object(
      'status','already_applied',
      'movement_id',movement_id,
      'current_stock',coalesce(new_stock,0),
      'server_authoritative',true
    );
    update public.idempotency_keys
    set response_status=200,response_body=result,completed_at=now()
    where id=idem.id;
    return result;
  end if;

  insert into public.product_stock_levels(product_id,location_id,current_stock,updated_at)
  values(target_product_id,target_location_id,0,now())
  on conflict(product_id,location_id) do nothing;

  update public.product_stock_levels
  set current_stock=current_stock + target_quantity_delta, updated_at=now()
  where product_id=target_product_id
    and location_id=target_location_id
    and current_stock + target_quantity_delta >= 0
  returning current_stock into new_stock;

  if not found then
    raise exception using errcode='22013',message='Inventory cannot become negative';
  end if;

  perform public._fulus_append_change(
    target_business_id,'inventory_movement',movement_id,'upsert',
    jsonb_build_object(
      'id',movement_id,
      'product_id',target_product_id,
      'location_id',target_location_id,
      'quantity_delta',target_quantity_delta,
      'reason',trim(target_reason),
      'current_stock',new_stock
    )
  );

  result := jsonb_build_object(
    'status','applied',
    'movement_id',movement_id,
    'current_stock',new_stock,
    'server_authoritative',true
  );
  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;
  return result;
end;
$function$;

create or replace function public.set_inventory_quantity(
  target_business_id uuid,
  target_product_id uuid,
  target_location_id uuid,
  target_new_quantity integer,
  target_reason text,
  target_operation_id text,
  target_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  product_business_id uuid;
  tracks_stock boolean;
  current_quantity integer;
  quantity_delta integer;
  movement_id uuid;
  actor uuid := auth.uid();
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
begin
  if target_new_quantity < 0 then
    raise exception using errcode = '22023', message = 'Stock quantity cannot be negative';
  end if;
  if actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode = '22023', message = 'operation_id is required';
  end if;
  if not exists (
    select 1 from public.business_memberships
    where business_id = target_business_id and user_id = actor and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'User is not an active member of this business';
  end if;
  if not exists (
    select 1 from public.devices
    where id = target_device_id and business_id = target_business_id and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Device is not registered or active';
  end if;

  request_hash := md5(jsonb_build_object(
    'business_id', target_business_id,
    'product_id', target_product_id,
    'location_id', target_location_id,
    'new_quantity', target_new_quantity,
    'reason', trim(target_reason),
    'device_id', target_device_id
  )::text);

  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  )
  values(
    target_business_id, target_device_id, actor, target_operation_id,
    'inventory.set', request_hash
  )
  on conflict(business_id,key) do nothing;

  select * into idem
  from public.idempotency_keys ik
  where ik.business_id=target_business_id and ik.key=target_operation_id
  for update;

  if idem.operation_type <> 'inventory.set' or idem.request_hash <> request_hash then
    raise exception using errcode='P0009', message='Operation id was already used with a different request';
  end if;

  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  select p.business_id, p.tracks_stock
    into product_business_id, tracks_stock
  from public.products p
  where p.id = target_product_id
  for update;

  if product_business_id is null or product_business_id <> target_business_id then
    raise exception using errcode = 'P0002', message = 'Product does not belong to this business';
  end if;
  if not coalesce(tracks_stock, false) then
    raise exception using errcode = '22023', message = 'Product does not track stock';
  end if;
  if not exists (
    select 1 from public.locations
    where id = target_location_id and business_id = target_business_id
  ) then
    raise exception using errcode = 'P0002', message = 'Location does not belong to this business';
  end if;

  insert into public.product_stock_levels(product_id, location_id, current_stock, updated_at)
  values (target_product_id, target_location_id, 0, now())
  on conflict (product_id, location_id) do nothing;

  select coalesce(ps.current_stock, 0)
    into current_quantity
  from public.product_stock_levels ps
  where ps.product_id = target_product_id and ps.location_id = target_location_id
  for update;

  quantity_delta := target_new_quantity - coalesce(current_quantity, 0);
  if quantity_delta = 0 then
    result := jsonb_build_object(
      'status', 'already_applied',
      'current_stock', current_quantity,
      'server_authoritative', true
    );
    update public.idempotency_keys
    set response_status=200,response_body=result,completed_at=now()
    where id=idem.id;
    return result;
  end if;

  insert into public.inventory_movements(
    business_id, product_id, location_id, quantity_delta, reason,
    operation_id, user_id, device_id
  )
  values (
    target_business_id, target_product_id, target_location_id, quantity_delta,
    trim(target_reason), target_operation_id, actor, target_device_id
  )
  returning id into movement_id;

  update public.product_stock_levels
  set current_stock = target_new_quantity, updated_at = now()
  where product_id = target_product_id and location_id = target_location_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Stock level row disappeared during absolute adjustment';
  end if;

  perform public._fulus_append_change(
    target_business_id,
    'inventory_movement',
    movement_id,
    'upsert',
    jsonb_build_object(
      'id', movement_id,
      'product_id', target_product_id,
      'location_id', target_location_id,
      'quantity_delta', quantity_delta,
      'reason', trim(target_reason),
      'current_stock', target_new_quantity
    )
  );

  result := jsonb_build_object(
    'status', 'applied',
    'movement_id', movement_id,
    'current_stock', target_new_quantity,
    'server_authoritative', true
  );
  update public.idempotency_keys
  set response_status=200,response_body=result,completed_at=now()
  where id=idem.id;
  return result;
end;
$function$;

-- Preserve the production command boundary: only the service role can invoke
-- these RPCs directly; the authenticated client reaches them through
-- fulus-api after the Edge Function validates the business/device context.
revoke execute on function public.apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid) from anon, authenticated;
revoke execute on function public.set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid) from anon, authenticated;
grant execute on function public.apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid) to service_role;
grant execute on function public.set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid) to service_role;
