-- Complete the sale-side stock change-feed emission. The previous migration
-- successfully hardened returns; this migration patches the multiline sale RPC
-- using a precise contract fragment and verifies the replacement happened.

do $$
declare
  oid oid;
  definition text;
  old_fragment text := $old$
        target_client_reference || ':stock:' || product.id, actor, target_device_id
      );
$old$;
  new_fragment text := $new$
        target_client_reference || ':stock:' || product.id, actor, target_device_id
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
$new$;
begin
  select p.oid into oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and p.proname = 'create_sale_atomic'
  limit 1;

  definition := pg_get_functiondef(oid);

  if position('''stock_movement''' in definition) > 0 then
    return;
  end if;

  definition := replace(
    definition,
    '  ledger_id uuid;' || chr(10) || 'begin',
    '  ledger_id uuid;' || chr(10) ||
    '  movement_id uuid;' || chr(10) ||
    '  current_quantity integer;' || chr(10) ||
    'begin'
  );

  if position(old_fragment in definition) = 0 then
    raise exception 'Sale inventory movement fragment was not found; refusing partial migration';
  end if;

  definition := replace(definition, old_fragment, new_fragment);
  execute definition;
end $$;
