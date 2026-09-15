-- Canonical Fulus Cloud sync contracts for the two remaining P0 finance/cash entities.
-- These tables are server-owned; mobile writes only through the RPCs below.

create table if not exists public.income_records (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  source text not null,
  amount numeric not null check (amount > 0),
  income_date timestamptz not null,
  notes text,
  client_reference text not null,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, client_reference)
);

create index if not exists income_records_business_date_idx
  on public.income_records (business_id, income_date desc);

create table if not exists public.cash_drawer_shifts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  cashier_user_id uuid not null references auth.users(id) on delete restrict,
  location_id uuid not null references public.locations(id) on delete restrict,
  opened_at timestamptz not null,
  closed_at timestamptz,
  opening_cash numeric not null check (opening_cash >= 0),
  closing_cash numeric check (closing_cash >= 0),
  cash_difference numeric,
  closing_note text,
  closing_summary_locked boolean not null default false,
  open_operation_id text not null,
  close_operation_id text,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, open_operation_id),
  unique (business_id, close_operation_id)
);

create unique index if not exists cash_drawer_shifts_one_open_per_location_idx
  on public.cash_drawer_shifts (business_id, location_id)
  where closed_at is null;

create index if not exists cash_drawer_shifts_business_opened_idx
  on public.cash_drawer_shifts (business_id, opened_at desc);

create or replace function public.cloud_record_income(
  target_business_id uuid,
  target_location_id uuid,
  target_source text,
  target_amount numeric,
  target_income_date timestamptz,
  target_notes text,
  target_operation_id text,
  target_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  existing public.income_records;
  created public.income_records;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  if not public.has_permission(target_business_id, 'finance.manage') then
    raise exception using errcode='42501', message='Finance permission required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='operation_id is required';
  end if;
  if target_source is null or length(trim(target_source)) = 0 then
    raise exception using errcode='22023', message='Income source is required';
  end if;
  if target_amount is null or target_amount <= 0 then
    raise exception using errcode='22013', message='Income amount must be greater than zero';
  end if;
  if not exists (
    select 1 from public.locations l
    where l.id = target_location_id and l.business_id = target_business_id and l.status = 'active'
  ) then
    raise exception using errcode='22023', message='Location does not belong to this business';
  end if;

  select * into existing
  from public.income_records
  where business_id = target_business_id and client_reference = target_operation_id;
  if found then
    return jsonb_build_object('status','already_applied','id',existing.id,'income_id',existing.id);
  end if;

  insert into public.income_records(
    business_id, location_id, source, amount, income_date, notes,
    client_reference, created_by, device_id
  ) values (
    target_business_id, target_location_id, trim(target_source), target_amount,
    target_income_date, nullif(trim(target_notes), ''), target_operation_id,
    actor, target_device_id
  ) returning * into created;

  perform public._fulus_append_change(
    target_business_id,
    'income',
    created.id,
    'upsert',
    jsonb_build_object(
      'id', created.id,
      'location_id', created.location_id,
      'source', created.source,
      'amount', created.amount,
      'income_date', created.income_date,
      'notes', created.notes,
      'client_reference', created.client_reference
    )
  );

  return jsonb_build_object('status','created','id',created.id,'income_id',created.id);
end;
$$;

create or replace function public.cloud_open_cash_drawer_shift(
  target_business_id uuid,
  target_location_id uuid,
  target_opening_cash numeric,
  target_opened_at timestamptz,
  target_operation_id text,
  target_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  existing public.cash_drawer_shifts;
  created public.cash_drawer_shifts;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  if not public.has_permission(target_business_id, 'cash.manage') then
    raise exception using errcode='42501', message='Cash permission required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='operation_id is required';
  end if;
  if target_opening_cash is null or target_opening_cash < 0 then
    raise exception using errcode='22013', message='Opening cash must be non-negative';
  end if;
  if not exists (
    select 1 from public.locations l
    where l.id = target_location_id and l.business_id = target_business_id and l.status = 'active'
  ) then
    raise exception using errcode='22023', message='Location does not belong to this business';
  end if;

  select * into existing
  from public.cash_drawer_shifts
  where business_id = target_business_id and open_operation_id = target_operation_id;
  if found then
    return jsonb_build_object('status','already_applied','id',existing.id,'shift_id',existing.id);
  end if;

  insert into public.cash_drawer_shifts(
    business_id, cashier_user_id, location_id, opened_at, opening_cash,
    open_operation_id, created_by, device_id
  ) values (
    target_business_id, actor, target_location_id, target_opened_at,
    target_opening_cash, target_operation_id, actor, target_device_id
  ) returning * into created;

  perform public._fulus_append_change(
    target_business_id,
    'cash_drawer_shift',
    created.id,
    'upsert',
    jsonb_build_object(
      'id', created.id,
      'cashier_user_id', created.cashier_user_id,
      'location_id', created.location_id,
      'opened_at', created.opened_at,
      'closed_at', created.closed_at,
      'opening_cash', created.opening_cash,
      'closing_cash', created.closing_cash,
      'cash_difference', created.cash_difference,
      'closing_note', created.closing_note,
      'closing_summary_locked', created.closing_summary_locked
    )
  );

  return jsonb_build_object('status','created','id',created.id,'shift_id',created.id);
end;
$$;

create or replace function public.cloud_close_cash_drawer_shift(
  target_business_id uuid,
  target_shift_id uuid,
  target_closing_cash numeric,
  target_cash_difference numeric,
  target_closing_note text,
  target_closed_at timestamptz,
  target_operation_id text,
  target_device_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  existing public.cash_drawer_shifts;
  updated public.cash_drawer_shifts;
begin
  if actor is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  if not public.has_permission(target_business_id, 'cash.manage') then
    raise exception using errcode='42501', message='Cash permission required';
  end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then
    raise exception using errcode='22023', message='operation_id is required';
  end if;
  if target_closing_cash is null or target_closing_cash < 0 then
    raise exception using errcode='22013', message='Closing cash must be non-negative';
  end if;

  select * into existing
  from public.cash_drawer_shifts
  where business_id = target_business_id and close_operation_id = target_operation_id;
  if found then
    return jsonb_build_object('status','already_applied','id',existing.id,'shift_id',existing.id);
  end if;

  select * into existing
  from public.cash_drawer_shifts
  where id = target_shift_id and business_id = target_business_id;
  if not found then
    raise exception using errcode='P0002', message='Cash drawer shift not found';
  end if;
  if existing.closed_at is not null then
    raise exception using errcode='22013', message='Cash drawer shift is already closed';
  end if;

  update public.cash_drawer_shifts
  set closed_at = target_closed_at,
      closing_cash = target_closing_cash,
      cash_difference = target_cash_difference,
      closing_note = nullif(trim(target_closing_note), ''),
      closing_summary_locked = true,
      close_operation_id = target_operation_id,
      device_id = coalesce(target_device_id, device_id),
      updated_at = now()
  where id = target_shift_id
  returning * into updated;

  perform public._fulus_append_change(
    target_business_id,
    'cash_drawer_shift',
    updated.id,
    'upsert',
    jsonb_build_object(
      'id', updated.id,
      'cashier_user_id', updated.cashier_user_id,
      'location_id', updated.location_id,
      'opened_at', updated.opened_at,
      'closed_at', updated.closed_at,
      'opening_cash', updated.opening_cash,
      'closing_cash', updated.closing_cash,
      'cash_difference', updated.cash_difference,
      'closing_note', updated.closing_note,
      'closing_summary_locked', updated.closing_summary_locked
    )
  );

  return jsonb_build_object('status','updated','id',updated.id,'shift_id',updated.id);
end;
$$;

revoke all on public.income_records from anon, authenticated;
revoke all on public.cash_drawer_shifts from anon, authenticated;
grant select on public.income_records to authenticated;
grant select on public.cash_drawer_shifts to authenticated;

drop policy if exists income_records_select_member on public.income_records;
create policy income_records_select_member on public.income_records for select
using ((select public.has_permission(business_id, 'finance.read')));

drop policy if exists cash_drawer_shifts_select_member on public.cash_drawer_shifts;
create policy cash_drawer_shifts_select_member on public.cash_drawer_shifts for select
using ((select public.has_permission(business_id, 'cash.read')));

revoke execute on function public.cloud_record_income(uuid,uuid,text,numeric,timestamptz,text,text,uuid) from public, anon, authenticated;
revoke execute on function public.cloud_open_cash_drawer_shift(uuid,uuid,numeric,timestamptz,text,uuid) from public, anon, authenticated;
revoke execute on function public.cloud_close_cash_drawer_shift(uuid,uuid,numeric,numeric,text,timestamptz,text,uuid) from public, anon, authenticated;
