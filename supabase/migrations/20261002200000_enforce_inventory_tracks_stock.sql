-- Part 11: enforce the catalog stock-tracking invariant at the database boundary.
--
-- A product with tracks_stock=false must not accumulate inventory movements.
-- The absolute-set command already checked this explicitly, but the delta
-- command path did not. A trigger closes the gap for every privileged insert
-- path, including future inventory writers, without duplicating the full
-- command implementation.

create or replace function public.prevent_inventory_movement_for_nonstock_product()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  tracks_stock boolean;
begin
  select p.tracks_stock
    into tracks_stock
  from public.products p
  where p.id = new.product_id;

  if not coalesce(tracks_stock, false) then
    raise exception using
      errcode = '22023',
      message = 'Product does not track stock';
  end if;

  return new;
end;
$function$;

drop trigger if exists inventory_movements_require_stock_tracking
  on public.inventory_movements;

create trigger inventory_movements_require_stock_tracking
before insert on public.inventory_movements
for each row
execute function public.prevent_inventory_movement_for_nonstock_product();
