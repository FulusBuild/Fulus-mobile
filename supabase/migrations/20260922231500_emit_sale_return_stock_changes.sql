-- Emit canonical stock movement changes for sale/return inventory mutations.
-- Without these feed events, another device can reconcile the sale itself but
-- never learn about the authoritative stock decrement/increment.

do $$
declare
  fn record;
  definition text;
  sale_block text;
  return_block text;
begin
  select p.oid, n.nspname, p.proname
    into fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname = 'create_sale_atomic'
    order by p.oid desc
    limit 1;

  if fn.oid is not null then
    definition := pg_get_functiondef(fn.oid);
  else
    definition := null;
  end if;
  definition := replace(
    definition,
    '  ledger_id uuid;
begin',
    '  ledger_id uuid;
  movement_id uuid;
  current_quantity integer;
begin'
  );

  sale_block := $block$
      insert into public.inventory_movements(
        business_id, product_id, location_id, quantity_delta, reason,
        operation_id, user_id, device_id
      )
      values(
        target_business_id, product.id, target_location_id,
        -(item->>'quantity')::integer, 'sale ' || invoice,
        target_client_reference || ':stock:' || product.id, actor,
        target_device_id
      );
$block$;

  definition := replace(
    definition,
    sale_block,
    $replacement$
      insert into public.inventory_movements(
        business_id, product_id, location_id, quantity_delta, reason,
        operation_id, user_id, device_id
      )
      values(
        target_business_id, product.id, target_location_id,
        -(item->>'quantity')::integer, 'sale ' || invoice,
        target_client_reference || ':stock:' || product.id, actor,
        target_device_id
      )
      returning id into movement_id;

      select current_stock into current_quantity
      from public.product_stock_levels
      where product_id = product.id
        and location_id = target_location_id;

      perform public._fulus_append_change(
        target_business_id,
        'stock_movement',
        movement_id,
        'upsert',
        jsonb_build_object(
          'id', movement_id,
          'product_id', product.id,
          'location_id', target_location_id,
          'quantity_delta', -(item->>'quantity')::integer,
          'quantity', (item->>'quantity')::integer,
          'new_quantity', current_quantity,
          'movement_type', 'sale',
          'reason', 'sale ' || invoice
        )
      );
$replacement$
  );

  if definition is not null then
    execute definition;
  end if;

  select p.oid, n.nspname, p.proname
    into fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname = 'create_return_atomic'
    limit 1;

  if fn.oid is not null then
    definition := pg_get_functiondef(fn.oid);
  else
    definition := null;
  end if;
  if definition is not null then
    definition := replace(
      definition,
      'reversal numeric:=0; ledger_id uuid;',
      'reversal numeric:=0; ledger_id uuid; movement_id uuid; current_quantity integer;'
    );
  end if;

  return_block := $block$
     insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
     values(target_business_id,si.product_id,sale.location_id,(item->>'quantity')::integer,'return',target_client_reference||':stock:'||si.id,actor,target_device_id);
$block$;

  definition := replace(
    definition,
    return_block,
    $replacement$
     insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
     values(target_business_id,si.product_id,sale.location_id,(item->>'quantity')::integer,'return',target_client_reference||':stock:'||si.id,actor,target_device_id)
     returning id into movement_id;

     select current_stock into current_quantity
     from public.product_stock_levels
     where product_id = si.product_id
       and location_id = sale.location_id;

     perform public._fulus_append_change(
       target_business_id,
       'stock_movement',
       movement_id,
       'upsert',
       jsonb_build_object(
         'id', movement_id,
         'product_id', si.product_id,
         'location_id', sale.location_id,
         'quantity_delta', (item->>'quantity')::integer,
         'quantity', (item->>'quantity')::integer,
         'new_quantity', current_quantity,
         'movement_type', 'return',
         'reason', 'return'
       )
     );
$replacement$
  );

  if definition is not null then
    execute definition;
  end if;
end $;