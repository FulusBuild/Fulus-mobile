-- Run after a clean local Supabase migration reset. This verifies the
-- deployed schema retains the same location-scoped barcode invariant as
-- the mobile repository and local SQLite database.
do $$
declare
  index_definition text;
  mutate_definition text;
begin
  select pg_get_indexdef(indexrelid)
    into index_definition
  from pg_index
  where indexrelid = 'public.products_location_barcode_uq'::regclass
    and indisunique;

  if index_definition is null
     or position('business_id, location_id, barcode' in index_definition) = 0
     or position('deleted_at IS NULL' in index_definition) = 0
     or position('location_id IS NOT NULL' in index_definition) = 0
     or position('barcode IS NOT NULL' in index_definition) = 0 then
    raise exception 'FAIL: active location-owned product barcodes are not uniquely indexed';
  end if;

  select pg_get_functiondef(
    'public.cloud_catalog_mutate(uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text)'::regprocedure
  ) into mutate_definition;

  if position('tracks_stock' in mutate_definition) = 0 then
    raise exception 'FAIL: catalog mutations do not persist product stock tracking';
  end if;
  if (length(mutate_definition) -
      length(replace(mutate_definition,
        'coalesce((target_item->>''tracks_stock'')::boolean,true)', ''))) /
        length('coalesce((target_item->>''tracks_stock'')::boolean,true)') < 2 then
    raise exception 'FAIL: product create and update must both persist stock tracking';
  end if;
end
$$;

select 'PASS: product barcode uniqueness and stock-tracking sync invariants hold' as result;
