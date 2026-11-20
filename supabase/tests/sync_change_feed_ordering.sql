-- Contract checks for the per-business transaction-scoped change-feed lock.
-- Run only against the disposable migration-chain database.
do $$
declare
  helper_definition text;
  append_definition text;
  catalog_definition text;
begin
  helper_definition := pg_get_functiondef(
    to_regprocedure('public._fulus_lock_sync_feed(uuid)')
  );
  append_definition := pg_get_functiondef(
    to_regprocedure('public._fulus_append_change(uuid,text,uuid,text,jsonb)')
  );
  catalog_definition := pg_get_functiondef(
    to_regprocedure('public._fulus_catalog_change(uuid,text,uuid,text,jsonb)')
  );

  if helper_definition is null or append_definition is null or catalog_definition is null then
    raise exception 'Sync feed helper definitions must exist in the migrated schema';
  end if;
  if position('pg_advisory_xact_lock' in helper_definition) = 0 then
    raise exception 'Sync feed lock must be transaction-scoped';
  end if;
  if position('public._fulus_lock_sync_feed' in append_definition) = 0
     or position('public._fulus_lock_sync_feed' in append_definition) >
        position('insert into public.sync_changes' in append_definition) then
    raise exception 'Canonical append must lock its business before allocating a feed sequence';
  end if;
  if position('public._fulus_lock_sync_feed' in catalog_definition) = 0
     or position('public._fulus_lock_sync_feed' in catalog_definition) >
        position('insert into public.sync_changes' in catalog_definition) then
    raise exception 'Catalog trigger writes must lock their business before allocating a feed sequence';
  end if;
  if has_function_privilege('anon', 'public._fulus_lock_sync_feed(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public._fulus_lock_sync_feed(uuid)', 'EXECUTE') then
    raise exception 'Client roles must not acquire sync feed locks directly';
  end if;
end;
$$;

select 'PASS: change feed allocation is serialized per business before sequence allocation' as result;
