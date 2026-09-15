alter table public.income_records enable row level security;
alter table public.cash_drawer_shifts enable row level security;

alter table public.income_records force row level security;
alter table public.cash_drawer_shifts force row level security;

revoke all on public.income_records from anon, authenticated;
revoke all on public.cash_drawer_shifts from anon, authenticated;
grant select on public.income_records to authenticated;
grant select on public.cash_drawer_shifts to authenticated;
