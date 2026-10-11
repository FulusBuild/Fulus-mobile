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
