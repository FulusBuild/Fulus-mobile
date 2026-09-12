-- Fulus Backend — Phase 0 foundation
-- Local-first / server-optional architecture.
-- This migration establishes tenancy, identity, authorization, devices,
-- idempotency, sync cursors/change feed, and audit infrastructure.
-- Domain transaction tables are introduced in later migrations.

create extension if not exists pgcrypto;

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency_code text not null default 'NGN',
  timezone text not null default 'Africa/Lagos',
  status text not null default 'active'
    check (status in ('active', 'suspended', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  description text,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name),
  unique (business_id, id)
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table public.business_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null,
  foreign key (business_id, role_id)
    references public.roles(business_id, id),
  status text not null default 'active'
    check (status in ('invited', 'active', 'suspended', 'removed')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  code text,
  address text,
  timezone text,
  status text not null default 'active'
    check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, code),
  unique (business_id, id)
);

create table public.location_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (location_id, user_id),
  foreign key (business_id, location_id)
    references public.locations(business_id, id)
    on delete cascade
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  registered_by uuid not null references auth.users(id),
  device_client_id text not null,
  device_name text,
  platform text,
  app_version text,
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, device_client_id)
);

create table public.idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  device_id uuid,
  foreign key (business_id, device_id)
    references public.devices(business_id, id),
  user_id uuid references auth.users(id),
  key text not null,
  operation_type text not null,
  request_hash text not null,
  response_status integer,
  response_body jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (business_id, key)
);

create table public.sync_operations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  device_id uuid not null,
  foreign key (business_id, device_id)
    references public.devices(business_id, id),
  user_id uuid references auth.users(id),
  operation_id text not null,
  operation_type text not null,
  client_reference text,
  status text not null default 'received'
    check (status in ('received', 'processing', 'applied', 'rejected', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  error_code text,
  error_details jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (business_id, device_id, operation_id)
);

create table public.sync_changes (
  sequence bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null check (operation in ('upsert', 'delete')),
  payload jsonb,
  created_at timestamptz not null default now()
);

create index sync_changes_business_sequence_idx
  on public.sync_changes (business_id, sequence);

create index sync_changes_business_entity_idx
  on public.sync_changes (business_id, entity_type, entity_id, sequence);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid,
  actor_user_id uuid references auth.users(id),
  device_id uuid,
  foreign key (business_id, device_id)
    references public.devices(business_id, id),
  action text not null,
  entity_type text,
  entity_id uuid,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (business_id, location_id)
    references public.locations(business_id, id)
);

create index audit_events_business_created_idx
  on public.audit_events (business_id, created_at desc);

create index business_memberships_user_idx
  on public.business_memberships (user_id, status);

create index location_memberships_user_idx
  on public.location_memberships (user_id, status);

create index locations_business_idx
  on public.locations (business_id, status);

create index devices_business_idx
  on public.devices (business_id, status);

create index sync_operations_business_status_idx
  on public.sync_operations (business_id, status, received_at);

-- Generic updated_at trigger.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger businesses_set_updated_at
before update on public.businesses
for each row execute function public.set_updated_at();

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row execute function public.set_updated_at();

create trigger business_memberships_set_updated_at
before update on public.business_memberships
for each row execute function public.set_updated_at();

create trigger locations_set_updated_at
before update on public.locations
for each row execute function public.set_updated_at();

create trigger location_memberships_set_updated_at
before update on public.location_memberships
for each row execute function public.set_updated_at();

create trigger devices_set_updated_at
before update on public.devices
for each row execute function public.set_updated_at();

-- Security-definer membership helpers. These intentionally bypass RLS on the
-- membership tables to avoid recursive policy evaluation. They are narrowly
-- scoped and only expose boolean answers to policy expressions.
create or replace function public.is_business_member(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  );
$$;

create or replace function public.is_business_admin(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and r.name in ('owner', 'admin')
  );
$$;

create or replace function public.is_location_member(target_location_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.location_memberships lm
    where lm.location_id = target_location_id
      and lm.user_id = auth.uid()
      and lm.status = 'active'
  );
$$;

create or replace function public.has_permission(target_business_id uuid, permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.role_permissions rp on rp.role_id = bm.role_id
    join public.permissions p on p.id = rp.permission_id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and p.code = permission_code
  );
$$;

-- Permission delegation helper. An administrator may only grant/revoke a
-- permission that the administrator already possesses. This prevents a manager
-- from escalating privileges beyond their own authorization scope.
create or replace function public.can_manage_role_permission(
  target_business_id uuid,
  target_role_id uuid,
  target_permission_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.roles actor_role on actor_role.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and actor_role.name = 'owner'
      and exists (
        select 1
        from public.roles target_role
        where target_role.id = target_role_id
          and target_role.business_id = target_business_id
      )
  )
  or exists (
    select 1
    from public.business_memberships bm
    join public.roles actor_role on actor_role.id = bm.role_id
    join public.role_permissions actor_rp on actor_rp.role_id = actor_role.id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and actor_role.name = 'admin'
      and actor_rp.permission_id = target_permission_id
      and exists (
        select 1
        from public.roles target_role
        where target_role.id = target_role_id
          and target_role.business_id = target_business_id
      )
  );
$$;

-- RLS is enabled on every exposed business table. Domain-specific tables in
-- later migrations follow the same business/location isolation pattern.
alter table public.businesses enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.business_memberships enable row level security;
alter table public.locations enable row level security;
alter table public.location_memberships enable row level security;
alter table public.devices enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.sync_operations enable row level security;
alter table public.sync_changes enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_select_own
on public.profiles for select
using (id = auth.uid());

create policy profiles_insert_own
on public.profiles for insert
with check (id = auth.uid());

create policy profiles_update_own
on public.profiles for update
using (id = auth.uid())
with check (id = auth.uid());

create policy businesses_select_member
on public.businesses for select
using (public.is_business_member(id));

create policy businesses_update_admin
on public.businesses for update
using (public.is_business_admin(id))
with check (public.is_business_admin(id));

create policy business_memberships_select_member
on public.business_memberships for select
using (user_id = auth.uid() or public.is_business_member(business_id));

create policy business_memberships_manage_admin
on public.business_memberships for all
using (public.is_business_admin(business_id))
with check (public.is_business_admin(business_id));

create policy roles_select_member
on public.roles for select
using (public.is_business_member(business_id));

create policy roles_manage_admin
on public.roles for all
using (public.is_business_admin(business_id))
with check (public.is_business_admin(business_id));

create policy role_permissions_select_member
on public.role_permissions for select
using (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and public.is_business_member(r.business_id)
  )
);

create policy role_permissions_manage_admin
on public.role_permissions for all
using (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and public.can_manage_role_permission(r.business_id, role_permissions.role_id, role_permissions.permission_id)
  )
)
with check (
  exists (
    select 1 from public.roles r
    where r.id = role_permissions.role_id
      and public.can_manage_role_permission(r.business_id, role_permissions.role_id, role_permissions.permission_id)
  )
);

create policy permissions_select_authenticated
on public.permissions for select
using (auth.uid() is not null);

create policy locations_select_member
on public.locations for select
using (public.is_business_member(business_id));

create policy locations_manage_admin
on public.locations for all
using (public.is_business_admin(business_id))
with check (public.is_business_admin(business_id));

create policy location_memberships_select_member
on public.location_memberships for select
using (user_id = auth.uid() or public.is_business_member(business_id));

create policy location_memberships_manage_admin
on public.location_memberships for all
using (public.is_business_admin(business_id))
with check (public.is_business_admin(business_id));

create policy devices_select_member
on public.devices for select
using (public.is_business_member(business_id));

create policy devices_manage_admin
on public.devices for all
using (public.is_business_admin(business_id))
with check (public.is_business_admin(business_id));

create policy idempotency_select_member
on public.idempotency_keys for select
using (public.is_business_member(business_id));

create policy sync_operations_select_member
on public.sync_operations for select
using (public.is_business_member(business_id));

create policy sync_changes_select_member
on public.sync_changes for select
using (public.is_business_member(business_id));

create policy audit_events_select_member
on public.audit_events for select
using (public.is_business_member(business_id));

-- Writes to idempotency, sync, and audit tables are deliberately absent from
-- client RLS. They are server-owned records and will be written by privileged
-- Edge Functions / transactional RPCs after authenticating the caller.

-- Seed the permission vocabulary used by the application. Roles are created
-- per business because permissions and membership are tenant-scoped.
insert into public.permissions (code, description) values
  ('business.read', 'View business settings and metadata'),
  ('business.manage', 'Manage business settings'),
  ('locations.read', 'View locations'),
  ('locations.manage', 'Create, edit, archive and manage locations'),
  ('employees.read', 'View employees and memberships'),
  ('employees.manage', 'Manage employees and memberships'),
  ('catalog.read', 'View products, categories and suppliers'),
  ('catalog.manage', 'Create, edit and archive catalog records'),
  ('inventory.read', 'View inventory and stock history'),
  ('inventory.adjust', 'Adjust stock'),
  ('inventory.transfer', 'Transfer stock between locations'),
  ('sales.read', 'View sales'),
  ('sales.create', 'Create sales'),
  ('sales.void', 'Void sales'),
  ('returns.create', 'Create returns'),
  ('returns.approve', 'Approve returns requiring supervision'),
  ('customers.read', 'View customers and credit'),
  ('customers.manage', 'Manage customers'),
  ('credit.manage', 'Record and adjust customer credit'),
  ('cash.read', 'View cash drawer activity'),
  ('cash.manage', 'Open, move and close cash drawer shifts'),
  ('finance.read', 'View income and expenses'),
  ('finance.manage', 'Manage income and expenses'),
  ('reports.read', 'View reports'),
  ('audit.read', 'View audit events')
on conflict (code) do nothing;

comment on table public.businesses is 'Fulus tenant/business boundary.';
comment on table public.business_memberships is 'Maps authenticated users to businesses and roles.';
comment on table public.location_memberships is 'Restricts users to the locations they may operate.';
comment on table public.idempotency_keys is 'Server-side deduplication for retryable mutations.';
comment on table public.sync_operations is 'Durable record of client sync operations.';
comment on table public.sync_changes is 'Monotonic per-database change feed consumed by offline clients.';
comment on table public.audit_events is 'Business audit trail; financial/inventory history is never hard-deleted.';
