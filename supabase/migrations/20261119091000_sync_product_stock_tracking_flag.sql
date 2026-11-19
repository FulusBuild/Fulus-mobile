-- Keep the product's stock-tracking choice canonical across devices.
-- The column existed in Postgres, but catalog mutation and mobile sync did
-- not include it, so a later pull silently restored the server default.
do $patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.cloud_catalog_mutate(uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text)'::regprocedure
  );
  v_patched := v_definition;

  v_old := 'low_stock_threshold,is_active,photo_path';
  v_new := 'low_stock_threshold,is_active,tracks_stock,photo_path';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'coalesce((target_item->>''is_active'')::boolean,true),\n' ||
    E'            nullif(target_item->>''photo_path'','''')';
  v_new := E'coalesce((target_item->>''is_active'')::boolean,true),\n' ||
    E'            coalesce((target_item->>''tracks_stock'')::boolean,true),\n' ||
    E'            nullif(target_item->>''photo_path'','''')';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'is_active=coalesce((target_item->>''is_active'')::boolean,true),\n';
  v_new := E'is_active=coalesce((target_item->>''is_active'')::boolean,true),\n' ||
    E'              tracks_stock=coalesce((target_item->>''tracks_stock'')::boolean,true),\n';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition
     or position('is_active,tracks_stock,photo_path' in v_patched) = 0
     or position('tracks_stock=coalesce((target_item->>''tracks_stock'')::boolean,true)' in v_patched) = 0 then
    raise exception 'cloud_catalog_mutate stock-tracking patch did not apply';
  end if;

  if (length(v_patched) -
      length(replace(v_patched,
        'coalesce((target_item->>''tracks_stock'')::boolean,true)', ''))) /
        length('coalesce((target_item->>''tracks_stock'')::boolean,true)') < 2 then
    raise exception 'cloud_catalog_mutate does not use tracks_stock for create and update';
  end if;

  execute v_patched;
end;
$patch$;
