-- Cloud Sync V1: make stock adjustments authoritative and replay-safe.
-- An adjustment is an absolute counted quantity, not a client-computed delta.
-- The product row is locked while the current stock is read so the delta is
-- derived from the server's latest authoritative value at commit time.

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
as $$
declare
  product_business_id uuid;
  tracks_stock boolean;
  current_quantity integer;
  quantity_delta integer;
begin
  if target_new_quantity < 0 then
    raise exception using errcode = '22023', message = 'Stock quantity cannot be negative';
  end if;

  if not exists (
    select 1 from public.business_memberships
    where business_id = target_business_id
      and user_id = auth.uid()
      and status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'User is not an active member of this business';
  end if;

  if not exists (
    select 1 from public.devices
    where id = target_device_id
      and business_id = target_business_id
      and status = 'active'
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
    select 1 from public.locations l
    where l.id = target_location_id
      and l.business_id = target_business_id
  ) then
    raise exception using errcode = 'P0002', message = 'Location does not belong to this business';
  end if;

  select coalesce(ps.current_stock, 0)
    into current_quantity
  from public.product_stock_levels ps
  where ps.product_id = target_product_id
    and ps.location_id = target_location_id;

  quantity_delta := target_new_quantity - coalesce(current_quantity, 0);

  return public.apply_inventory_adjustment(
    target_business_id,
    target_product_id,
    target_location_id,
    quantity_delta,
    target_reason,
    target_operation_id,
    target_device_id
  );
end;
$$;

create or replace function public.fulus_api_set_inventory_quantity(
  target_user_id uuid,
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
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.set_inventory_quantity(
    target_business_id,
    target_product_id,
    target_location_id,
    target_new_quantity,
    target_reason,
    target_operation_id,
    target_device_id
  );
end;
$$;

revoke execute on function public.set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid) from public, anon, authenticated;
revoke execute on function public.fulus_api_set_inventory_quantity(uuid,uuid,uuid,uuid,integer,text,text,uuid) from public, anon, authenticated;
