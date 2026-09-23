-- Bring the production expense row shape in line with the current sync contract.
-- Additive only: existing expense data remains intact.
alter table public.expenses
  add column if not exists updated_at timestamptz not null default now();

alter table public.expenses
  add column if not exists deleted_at timestamptz;

update public.expenses
set updated_at = coalesce(updated_at, created_at, now())
where updated_at is null;


