-- Preserve the idempotency identity in stock movement change events so the
-- mobile optimistic row can be reconciled even when the feed wins the race
-- with the command response.
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
set search_path = ''
as $function$
declare
  new_sequence bigint;
  canonical_payload jsonb := target_payload;
  movement_created_at timestamptz;
  movement_operation_id text;
begin
  if target_operation not in ('upsert', 'delete') then
    raise exception using errcode = '22023', message = 'Invalid change operation';
  end if;

  if target_business_id is null then
    raise exception using errcode = '22023', message = 'business_id is required for a sync change';
  end if;

  if target_entity_type = 'stock_movement'
     and target_operation = 'upsert'
     and target_entity_id is not null then
    select im.created_at, im.operation_id
      into movement_created_at, movement_operation_id
    from public.inventory_movements im
    where im.id = target_entity_id
      and im.business_id = target_business_id;

    if movement_created_at is not null then
      canonical_payload := canonical_payload
        || jsonb_build_object(
          'created_at', movement_created_at,
          'updated_at', movement_created_at,
          'operation_id', movement_operation_id
        );
    end if;
  end if;

  perform public._fulus_lock_sync_feed(target_business_id);

  insert into public.sync_changes (
    business_id, entity_type, entity_id, operation, payload
  )
  values (
    target_business_id,
    target_entity_type,
    target_entity_id,
    target_operation,
    canonical_payload
  )
  returning sequence into new_sequence;

  return new_sequence;
end;
$function$;

revoke execute on function public._fulus_append_change(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;

update public.sync_changes sc
set payload = sc.payload || jsonb_build_object('operation_id', im.operation_id)
from public.inventory_movements im
where sc.entity_type = 'stock_movement'
  and sc.operation = 'upsert'
  and sc.entity_id = im.id
  and sc.business_id = im.business_id
  and sc.payload->>'operation_id' is null;
