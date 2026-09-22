-- Cloud Sync V1: make absolute stock targets atomic under concurrent callers.
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
set search_path = public
as $function$
declare
  product_business_id uuid;
  tracks_stock boolean;
  current_quantity integer;
  quantity_delta integer;
  movement_id uuid;
begin
  if target_new_quantity < 0 then
    raise exception using errcode = '22023', message = 'Stock quantity cannot be negative';
  end if;
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not exists (
    select 1 from public.business_memberships
    where business_id = target_business_id and user_id = auth.uid() and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'User is not an active member of this business';
  end if;
  if not exists (
    select 1 from public.devices
    where id = target_device_id and business_id = target_business_id and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Device is not registered or active';
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

  select im.id
    into movement_id
  from public.inventory_movements im
  where im.business_id = target_business_id and im.operation_id = target_operation_id
  limit 1;

  if movement_id is not null then
    return jsonb_build_object(
      'status', 'already_applied',
      'movement_id', movement_id,
      'current_stock', current_quantity,
      'server_authoritative', true
    );
  end if;

  quantity_delta := target_new_quantity - coalesce(current_quantity, 0);
  if quantity_delta = 0 then
    return jsonb_build_object(
      'status', 'already_applied',
      'current_stock', current_quantity,
      'server_authoritative', true
    );
  end if;

  insert into public.inventory_movements(
    business_id, product_id, location_id, quantity_delta, reason,
    operation_id, user_id, device_id
  )
  values (
    target_business_id, target_product_id, target_location_id, quantity_delta,
    trim(target_reason), target_operation_id, auth.uid(), target_device_id
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

  return jsonb_build_object(
    'status', 'applied',
    'movement_id', movement_id,
    'current_stock', target_new_quantity,
    'server_authoritative', true
  );
end;
$function$;