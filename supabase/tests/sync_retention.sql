-- Sync retention watermark contract tests.
-- Run with a privileged SQL role against a disposable/branch database.

do $$
declare
  function_def text;
begin
  if to_regclass('public.sync_change_retention_watermarks') is null then
    raise exception 'Per-business sync retention watermark table is missing';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sync_change_retention_watermarks'
      and c.relrowsecurity
  ) then
    raise exception 'Sync retention watermark table must have RLS enabled';
  end if;

  if has_table_privilege('anon', 'public.sync_change_retention_watermarks', 'SELECT')
     or has_table_privilege('authenticated', 'public.sync_change_retention_watermarks', 'SELECT')
     or has_table_privilege('anon', 'public.sync_change_retention_watermarks', 'INSERT')
     or has_table_privilege('authenticated', 'public.sync_change_retention_watermarks', 'INSERT') then
    raise exception 'Client roles must not read or mutate sync retention watermarks directly';
  end if;

  function_def := pg_get_functiondef(to_regprocedure('public.prune_sync_changes()'));
  if position('sync_change_retention_watermarks' in function_def) = 0 then
    raise exception 'Retention pruning must maintain per-business watermarks';
  end if;
  if position('max(sequence)' in function_def) = 0 then
    raise exception 'Retention watermark must record the highest pruned sequence per business';
  end if;
  if position('greatest(' in lower(function_def)) = 0 then
    raise exception 'Retention watermark must be monotonic across pruning batches';
  end if;
end;
$$;

select 'PASS: sync retention uses monotonic per-business watermarks' as result;

-- Exercise pruning against isolated, transactional fixtures. Global sequence
-- values are shared across businesses; only rows actually pruned for a given
-- business may advance that business's watermark. The rollback leaves the
-- disposable migration-chain database unchanged for subsequent tests.
begin;
do $$
declare
  business_a uuid;
  business_b uuid;
  business_sparse uuid;
  business_empty uuid;
  expected_a bigint;
  expected_b bigint;
  actual_watermark bigint;
  pruned_count bigint;
begin
  insert into public.businesses (name) values ('sync-retention-test-a')
    returning id into business_a;
  insert into public.businesses (name) values ('sync-retention-test-b')
    returning id into business_b;
  insert into public.businesses (name) values ('sync-retention-test-sparse')
    returning id into business_sparse;
  insert into public.businesses (name) values ('sync-retention-test-empty')
    returning id into business_empty;

  -- Interleave business rows so each feed has gaps in the global identity.
  insert into public.sync_changes
    (business_id, entity_type, entity_id, operation, payload, created_at)
  values
    (business_a, 'retention_test', gen_random_uuid(), 'upsert', '{}'::jsonb, now() - interval '100 days'),
    (business_b, 'retention_test', gen_random_uuid(), 'upsert', '{}'::jsonb, now() - interval '100 days'),
    (business_a, 'retention_test', gen_random_uuid(), 'delete', '{}'::jsonb, now() - interval '100 days');

  -- The sparse business has a retained row despite the intervening global
  -- sequence values allocated to other businesses.
  insert into public.sync_changes
    (business_id, entity_type, entity_id, operation, payload, created_at)
  values
    (business_sparse, 'retention_test', gen_random_uuid(), 'upsert', '{}'::jsonb, now());

  select max(sequence) into expected_a
  from public.sync_changes
  where business_id = business_a and created_at < now() - interval '90 days';
  select max(sequence) into expected_b
  from public.sync_changes
  where business_id = business_b and created_at < now() - interval '90 days';

  pruned_count := public.prune_sync_changes();
  if pruned_count < 3 then
    raise exception 'Expected at least the three expired test rows to be pruned; got %', pruned_count;
  end if;

  select pruned_through_sequence into actual_watermark
  from public.sync_change_retention_watermarks
  where business_id = business_a;
  if actual_watermark is distinct from expected_a then
    raise exception 'Business A watermark %, expected highest actually pruned sequence %', actual_watermark, expected_a;
  end if;

  select pruned_through_sequence into actual_watermark
  from public.sync_change_retention_watermarks
  where business_id = business_b;
  if actual_watermark is distinct from expected_b then
    raise exception 'Business B watermark %, expected highest actually pruned sequence %', actual_watermark, expected_b;
  end if;

  if exists (
    select 1 from public.sync_change_retention_watermarks
    where business_id = business_sparse
  ) then
    raise exception 'A sparse feed with no pruned rows must not receive a retention watermark';
  end if;
  if exists (
    select 1 from public.sync_change_retention_watermarks
    where business_id = business_empty
  ) then
    raise exception 'An empty feed must not receive a retention watermark';
  end if;

  -- Explicitly prove monotonicity even if a later pruning batch's maximum is
  -- lower than a previously recorded value (for example after data repair).
  update public.sync_change_retention_watermarks
  set pruned_through_sequence = 999999999
  where business_id = business_a;

  insert into public.sync_changes
    (business_id, entity_type, entity_id, operation, payload, created_at)
  values
    (business_a, 'retention_test', gen_random_uuid(), 'upsert', '{}'::jsonb, now() - interval '100 days');

  perform public.prune_sync_changes();

  select pruned_through_sequence into actual_watermark
  from public.sync_change_retention_watermarks
  where business_id = business_a;
  if actual_watermark <> 999999999 then
    raise exception 'Watermark regressed after another pruning batch: %', actual_watermark;
  end if;
end;
$$;
rollback;
