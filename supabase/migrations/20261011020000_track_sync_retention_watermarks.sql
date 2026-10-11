-- A global identity sequence is sparse within each business because sequence
-- values are shared across all businesses. The oldest retained sequence for a
-- business therefore cannot prove that this business has pruned any changes.
-- Track the highest sequence actually pruned per business instead.
create table if not exists public.sync_change_retention_watermarks (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  pruned_through_sequence bigint not null default 0
    check (pruned_through_sequence >= 0),
  updated_at timestamptz not null default now()
);

alter table public.sync_change_retention_watermarks enable row level security;
revoke all on table public.sync_change_retention_watermarks from public, anon, authenticated;

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
    with deleted as (
      delete from public.sync_changes
      where ctid in (
        select ctid
        from public.sync_changes
        where created_at < now() - interval '90 days'
        order by created_at, sequence
        limit 5000
      )
      returning business_id, sequence
    ),
    updated_watermarks as (
      insert into public.sync_change_retention_watermarks (
        business_id,
        pruned_through_sequence,
        updated_at
      )
      select business_id, max(sequence), now()
      from deleted
      group by business_id
      on conflict (business_id) do update
      set pruned_through_sequence = greatest(
            public.sync_change_retention_watermarks.pruned_through_sequence,
            excluded.pruned_through_sequence
          ),
          updated_at = now()
      returning business_id
    )
    select count(*) into batch_count from deleted;

    deleted_count := deleted_count + batch_count;
    exit when batch_count = 0;
  end loop;

  return deleted_count;
end;
$$;

revoke all on function public.prune_sync_changes() from public, anon, authenticated;
