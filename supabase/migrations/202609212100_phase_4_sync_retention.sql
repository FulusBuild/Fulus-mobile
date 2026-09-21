-- Phase 4 scale hardening: retain a bounded change feed and rely on
-- cursor-too-old bootstrap recovery for devices that fall behind the window.
--
-- Idempotency records are intentionally NOT pruned here. A very old device
-- may replay an outbound operation after a long offline period, so removing
-- idempotency keys would weaken the duplicate-effect guarantee.
create extension if not exists pg_cron;

create or replace function public.prune_sync_changes()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count bigint := 0;
  batch_count bigint;
begin
  loop
    delete from public.sync_changes
    where ctid in (
      select ctid
      from public.sync_changes
      where created_at < now() - interval '90 days'
      order by created_at, sequence
      limit 5000
    );

    get diagnostics batch_count = row_count;
    deleted_count := deleted_count + batch_count;
    exit when batch_count = 0;
  end loop;

  return deleted_count;
end;
$$;

revoke all on function public.prune_sync_changes() from public, anon, authenticated;

select cron.schedule(
  'fulus-sync-change-retention',
  '30 3 * * *',
  $$select public.prune_sync_changes();$$
)
where not exists (
  select 1 from cron.job where jobname = 'fulus-sync-change-retention'
);
