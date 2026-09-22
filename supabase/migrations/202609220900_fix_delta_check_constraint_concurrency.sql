-- Cloud Sync V1: make delta application safe for absolute-target concurrency.
-- The old INSERT ... ON CONFLICT path could reject a negative delta through
-- the stock_nonnegative CHECK constraint even when the final stock target was
-- valid (e.g. concurrent targets 101 and 202).
create or replace function public.apply_inventory_adjustment(
  target_business_id uuid,
  target_product_id uuid,
  target_location_id uuid,
  target_quantity_delta integer,
  target_reason text,
  target_operation_id text,
  target_device_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor uuid := auth.uid();
  new_stock integer;
  movement_id uuid;
begin
  if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
  if target_quantity_delta = 0 then raise exception using errcode='22023',message='Quantity delta cannot be zero'; end if;
  if not public.has_permission(target_business_id,'inventory.adjust') then raise exception using errcode='42501',message='Inventory adjustment permission required'; end if;
  if target_device_id is not null and not exists(
    select 1 from public.devices d where d.id=target_device_id and d.business_id=target_business_id and d.status='active'
  ) then raise exception using errcode='42501',message='Device is not active for this business'; end if;
  if not exists(select 1 from public.products p where p.id=target_product_id and p.business_id=target_business_id and p.deleted_at is null) then raise exception using errcode='22023',message='Product does not belong to business'; end if;
  if not exists(select 1 from public.locations l where l.id=target_location_id and l.business_id=target_business_id) then raise exception using errcode='22023',message='Location does not belong to business'; end if;

  insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
  values(target_business_id,target_product_id,target_location_id,target_quantity_delta,trim(target_reason),target_operation_id,actor,target_device_id)
  on conflict (business_id,operation_id) do nothing
  returning id into movement_id;

  if movement_id is null then
    select current_stock into new_stock from public.product_stock_levels
    where product_id=target_product_id and location_id=target_location_id;
    return jsonb_build_object('status','already_applied','movement_id',(select id from public.inventory_movements where business_id=target_business_id and operation_id=target_operation_id),'current_stock',coalesce(new_stock,0),'server_authoritative',true);
  end if;

  insert into public.product_stock_levels(product_id,location_id,current_stock,updated_at)
  values(target_product_id,target_location_id,0,now())
  on conflict(product_id,location_id) do nothing;

  update public.product_stock_levels
  set current_stock=current_stock + target_quantity_delta, updated_at=now()
  where product_id=target_product_id and location_id=target_location_id
    and current_stock + target_quantity_delta >= 0
  returning current_stock into new_stock;

  if not found then raise exception using errcode='22013',message='Inventory cannot become negative'; end if;

  perform public._fulus_append_change(target_business_id,'inventory_movement',movement_id,'upsert',
    jsonb_build_object('id',movement_id,'product_id',target_product_id,'location_id',target_location_id,
      'quantity_delta',target_quantity_delta,'reason',trim(target_reason),'current_stock',new_stock));

  return jsonb_build_object('status','applied','movement_id',movement_id,'current_stock',new_stock,'server_authoritative',true);
end;
$function$;