-- Remote mirror for the existing on-device Diagnostics system.
-- The mobile app remains local-first; this table is a best-effort diagnostic sink.
create table if not exists public.diagnostic_events (
  id text primary key,
  user_id uuid not null,
  business_id uuid null,
  device_client_id text null,
  severity text not null check (severity in ('info','warning','error','critical')),
  category text not null,
  title text not null,
  message text not null,
  component text null,
  operation text null,
  screen text null,
  exception_type text null,
  error_code text null,
  failure_stage text null,
  occurrence_count integer not null default 1,
  event_timestamp timestamptz not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  constraint diagnostic_events_id_len check (char_length(id) between 1 and 128)
);

create index if not exists diagnostic_events_user_created_idx
  on public.diagnostic_events(user_id, created_at desc);
create index if not exists diagnostic_events_business_created_idx
  on public.diagnostic_events(business_id, created_at desc);
create index if not exists diagnostic_events_device_created_idx
  on public.diagnostic_events(device_client_id, created_at desc);
create index if not exists diagnostic_events_category_created_idx
  on public.diagnostic_events(category, created_at desc);

alter table public.diagnostic_events enable row level security;
revoke all on public.diagnostic_events from anon, authenticated;
