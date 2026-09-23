create or replace function public._fulus_append_change(
  target_business_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_operation text,
  target_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path = 'public'
as $function$
declare
  new_sequence bigint;
  canonical_payload jsonb := target_payload;
  movement_created_at timestamptz;
begin
  if target_operation not in ('upsert','delete') then
    raise exception using errcode='22023', message='Invalid change operation';
  end if;

  -- Stock movement canonical rows must carry replayable timestamps. Older
  -- append callers omitted them, so enrich every stock movement event from
  -- the authoritative inventory movement row.
  if target_entity_type = 'stock_movement'
     and target_operation = 'upsert'
     and target_entity_id is not null then
    select im.created_at
      into movement_created_at
    from public.inventory_movements im
    where im.id = target_entity_id
      and im.business_id = target_business_id;

    if movement_created_at is not null then
      canonical_payload := canonical_payload
        || jsonb_build_object(
          'created_at', movement_created_at,
          'updated_at', movement_created_at
        );
    end if;
  end if;

  insert into public.sync_changes(
    business_id, entity_type, entity_id, operation, payload
  )
  values (
    target_business_id, target_entity_type, target_entity_id,
    target_operation, canonical_payload
  )
  returning sequence into new_sequence;

  return new_sequence;
end;
$function$;

-- Repair retained stock-movement events emitted before the timestamp
-- contract existed so existing devices can replay them safely.
update public.sync_changes sc
set payload = sc.payload
  || jsonb_build_object(
       'created_at', im.created_at,
       'updated_at', im.created_at
     )
from public.inventory_movements im
where sc.entity_type = 'stock_movement'
  and sc.operation = 'upsert'
  and sc.entity_id = im.id
  and sc.business_id = im.business_id
  and (
    sc.payload->>'created_at' is null
    or sc.payload->>'updated_at' is null
  );