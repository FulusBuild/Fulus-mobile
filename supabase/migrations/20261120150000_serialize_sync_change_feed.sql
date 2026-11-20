-- Per-business cursors acknowledge every returned sequence. PostgreSQL
-- identity values are allocated before a transaction commits, so concurrent
-- mutations could otherwise commit sequence 42 before an earlier, still-open
-- sequence 41. A client that acknowledges 42 would then never see 41.
-- Serialize change-feed insertion per business and hold the lock to commit.
create or replace function public._fulus_lock_sync_feed(target_business_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if target_business_id is null then
    raise exception using errcode = '22023', message = 'business_id is required for a sync change';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('fulus.sync_changes:' || target_business_id::text, 0)
  );
end;
$function$;

revoke all on function public._fulus_lock_sync_feed(uuid)
  from public, anon, authenticated;

create or replace function public._fulus_catalog_change(
  target_business_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_operation text,
  target_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public._fulus_lock_sync_feed(target_business_id);

  insert into public.sync_changes (
    business_id, entity_type, entity_id, operation, payload
  )
  values (
    target_business_id,
    target_entity_type,
    target_entity_id,
    target_operation,
    target_payload
  );
end;
$function$;

revoke execute on function public._fulus_catalog_change(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;

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
begin
  if target_operation not in ('upsert', 'delete') then
    raise exception using errcode = '22023', message = 'Invalid change operation';
  end if;

  if target_business_id is null then
    raise exception using errcode = '22023', message = 'business_id is required for a sync change';
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

  -- This transaction-scoped lock is acquired before identity allocation and
  -- held until the caller commits. Distinct businesses remain independent.
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
