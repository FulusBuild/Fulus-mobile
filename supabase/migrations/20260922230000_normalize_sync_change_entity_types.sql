-- Normalize canonical change-feed entity names to the mobile sync contract.
-- The underlying SQL tables remain inventory_movements/income_records; only
-- sync_changes entity_type is normalized.

do $$
declare
  fn record;
  definition text;
begin
  for fn in
    select p.oid, n.nspname, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname in (
        'apply_inventory_adjustment',
        'set_inventory_quantity',
        'create_return_atomic',
        'create_sale_atomic',
        'cloud_catalog_mutate'
      )
  loop
    definition := pg_get_functiondef(fn.oid);
    definition := replace(definition, '''inventory_movement''', '''stock_movement''');
    execute definition;
  end loop;
end $$;

create or replace function public.cloud_record_income(
  target_business_id uuid,
  target_location_id uuid,
  target_source text,
  target_amount numeric,
  target_income_date timestamptz,
  target_notes text,
  target_operation_id text,
  target_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  existing public.income_records;
  created public.income_records;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  if not public.has_permission(target_business_id, 'finance.manage') then
    raise exception using errcode='42501', message='Finance permission required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='operation_id is required';
  end if;
  if target_source is null or length(trim(target_source)) = 0 then
    raise exception using errcode='22023', message='Income source is required';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception using errcode='22013', message='Income amount must be greater than zero';
  end if;
  if not exists (
    select 1 from public.locations l
    where l.id = target_location_id
      and l.business_id = target_business_id
      and l.status = 'active'
  ) then
    raise exception using errcode='22023', message='Location does not belong to this business';
  end if;

  select * into existing
  from public.income_records
  where business_id = target_business_id
    and client_reference = target_operation_id;

  if found then
    return jsonb_build_object(
      'status','already_applied',
      'id',existing.id,
      'income_id',existing.id
    );
  end if;

  insert into public.income_records(
    business_id, location_id, source, amount, income_date, notes,
    client_reference, created_by, device_id
  )
  values (
    target_business_id,
    target_location_id,
    trim(target_source),
    target_amount,
    target_income_date,
    nullif(trim(target_notes), ''),
    target_operation_id,
    actor,
    target_device_id
  )
  returning * into created;

  perform public._fulus_append_change(
    target_business_id,
    'income_record',
    created.id,
    'upsert',
    jsonb_build_object(
      'id', created.id,
      'location_id', created.location_id,
      'source', created.source,
      'amount', created.amount,
      'income_date', created.income_date,
      'notes', created.notes,
      'client_reference', created.client_reference
    )
  );

  return jsonb_build_object(
    'status','created',
    'id',created.id,
    'income_id',created.id
  );
end;
$$;

update public.sync_changes
set entity_type = 'stock_movement'
where entity_type = 'inventory_movement';

update public.sync_changes
set entity_type = 'income_record'
where entity_type = 'income';
