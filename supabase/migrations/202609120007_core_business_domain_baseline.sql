-- Fulus backend core business-domain baseline.
--
-- The original production deployment was assembled through migrations that
-- were applied from an earlier repository state, while the current Git
-- history retained only marker migrations for several core tables. This
-- baseline restores fresh-environment reproducibility without changing the
-- already-created production tables.
--
-- It intentionally contains only the durable table shapes and core
-- constraints. RLS, indexes, triggers and server mutation functions remain
-- owned by the later hardening migrations in this directory.

-- Legacy catalog change helper retained only so the subsequent
-- hardening migration can explicitly revoke direct execution. Current
-- catalog writes use the actor-bound service wrapper.
-- Legacy customer mutation helpers. Later migrations replace these
-- signatures with idempotent/actor-bound wrappers and explicitly revoke the
-- old service-role execution. Define inert functions here so a fresh replay
-- can execute those lockdown migrations without depending on historical state.
create or replace function public.create_customer(
  target_business_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_credit_limit numeric
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy customer RPC is disabled';
end;
$function$;

create or replace function public.create_customer(
  target_business_id uuid,
  target_name text,
  target_phone text,
  target_email text,
  target_address text,
  target_credit_limit numeric,
  target_notes text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy customer RPC is disabled';
end;
$function$;

revoke all on function public.create_customer(
  uuid,text,text,text,text,numeric
) from public, anon, authenticated, service_role;

revoke all on function public.create_customer(
  uuid,text,text,text,text,numeric,text
) from public, anon, authenticated, service_role;

create or replace function public._fulus_catalog_change(
  target_business_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_operation text,
  target_payload jsonb
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.sync_changes (
    business_id, entity_type, entity_id, operation, payload
  )
  values (
    target_business_id,
    target_entity_type,
    target_entity_id,
    target_operation,
    target_payload
  );
end;
$function$;

revoke execute on function public._fulus_catalog_change(
  uuid, text, uuid, text, jsonb
) from public, anon, authenticated;

-- Legacy 8-argument sync-operation overload. It existed in an earlier
-- API contract and later security migrations explicitly revoke it. Keep it
-- in the fresh-schema history so those lockdown migrations remain replayable,
-- but make it unusable as a direct privileged entry point.
create or replace function public.accept_sync_operation(
  target_business_id uuid,
  target_device_id uuid,
  target_user_id uuid,
  target_operation_id text,
  target_operation_type text,
  target_client_reference text,
  target_request_hash text,
  target_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return public.accept_sync_operation(
    target_business_id,
    target_device_id,
    target_user_id,
    target_operation_id,
    target_operation_type,
    target_client_reference,
    target_request_hash
  );
end;
$function$;

revoke execute on function public.accept_sync_operation(
  uuid, uuid, uuid, text, text, text, text, jsonb
) from public, anon, authenticated, service_role;

-- Legacy actor-suffixed staff overloads. Later migrations explicitly
-- revoke these historical signatures after replacing them with server-bound
-- wrappers. Define inert versions here so a fresh migration replay has the
-- same objects available for lockdown.
create or replace function public.create_staff_invite(
  target_business_id uuid, target_role_id uuid, target_email text,
  target_expires_hours integer, target_user_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy staff RPC overload is disabled';
end;
$function$;

create or replace function public.claim_staff_invite(
  target_token text, target_user_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy staff RPC overload is disabled';
end;
$function$;

create or replace function public.set_member_status(
  target_business_id uuid, target_membership_id uuid, target_status text,
  target_user_id uuid
) returns boolean language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy staff RPC overload is disabled';
end;
$function$;

create or replace function public.change_member_role(
  target_business_id uuid, target_membership_id uuid, target_role_id uuid,
  target_user_id uuid
) returns boolean language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy staff RPC overload is disabled';
end;
$function$;

create or replace function public.set_role_permission(
  target_business_id uuid, target_role_id uuid, target_permission_id uuid,
  enabled boolean, target_user_id uuid
) returns boolean language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy staff RPC overload is disabled';
end;
$function$;

revoke all on function public.create_staff_invite(
  uuid,uuid,text,integer,uuid
) from public, anon, authenticated, service_role;
revoke all on function public.claim_staff_invite(text,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.set_member_status(uuid,uuid,text,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.change_member_role(uuid,uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.set_role_permission(uuid,uuid,uuid,boolean,uuid)
  from public, anon, authenticated, service_role;

-- Legacy lower-level mutation helpers retained only so the historical
-- lockdown migration can replay from an empty database. They are inert and
-- revoked later in the chain; current service wrappers no longer depend on
-- direct client execution of these helpers.

create or replace function public.set_inventory_quantity(
  target_business_id uuid, target_product_id uuid, target_location_id uuid,
  target_new_quantity integer, target_reason text, target_operation_id text,
  target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy inventory helper is disabled';
end;
$function$;

create or replace function public.cloud_open_cash_drawer_shift(
  target_business_id uuid, target_location_id uuid, target_opening_cash numeric,
  target_opened_at timestamptz, target_operation_id text, target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy cash drawer helper is disabled';
end;
$function$;

create or replace function public.cloud_record_income(
  target_business_id uuid, target_location_id uuid, target_source text,
  target_amount numeric, target_income_date timestamptz, target_notes text,
  target_operation_id text, target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy income helper is disabled';
end;
$function$;

create or replace function public.record_customer_repayment(
  target_business_id uuid, target_customer_id uuid, target_amount numeric,
  target_operation_id text, target_payment_method text, target_note text,
  target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy repayment helper is disabled';
end;
$function$;

create or replace function public.record_sale_payment(
  target_business_id uuid, target_sale_id uuid, target_amount numeric,
  target_operation_id text, target_payment_method text, target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy sale payment helper is disabled';
end;
$function$;

create or replace function public.record_expense(
  target_business_id uuid, target_location_id uuid, target_amount numeric,
  target_category text, target_description text, target_expense_date timestamptz,
  target_device_id uuid, target_request_hash text
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy expense helper is disabled';
end;
$function$;

create or replace function public.record_expense(
  target_business_id uuid, target_location_id uuid, target_amount numeric,
  target_category text, target_description text, target_expense_date timestamptz,
  target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy expense helper is disabled';
end;
$function$;

-- Legacy service API wrappers retained only so historical lockdown
-- migrations can be replayed from an empty database. They are inert and
-- executable by no role; the current actor/device-bound wrappers are defined
-- and granted later in the chain.
create or replace function public.fulus_api_create_customer(
  target_user_id uuid, target_business_id uuid, target_name text,
  target_phone text, target_email text, target_address text,
  target_credit_limit numeric
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy customer API wrapper is disabled';
end;
$function$;

create or replace function public.fulus_api_create_customer(
  target_user_id uuid, target_business_id uuid, target_name text,
  target_phone text, target_email text, target_address text,
  target_credit_limit numeric, target_notes text
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy customer API wrapper is disabled';
end;
$function$;

create or replace function public.fulus_api_update_customer(
  target_user_id uuid, target_business_id uuid, target_device_id uuid,
  target_operation_id text, target_customer_id uuid, target_name text,
  target_phone text, target_email text, target_address text,
  target_notes text, target_credit_limit numeric, target_is_active boolean,
  target_request_hash text
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy customer update API wrapper is disabled';
end;
$function$;

create or replace function public.fulus_api_update_expense(
  target_user_id uuid, target_business_id uuid, target_device_id uuid,
  target_operation_id text, target_expense_id uuid, target_location_id uuid,
  target_amount numeric, target_category text, target_description text,
  target_expense_date timestamptz, target_request_hash text
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy expense update API wrapper is disabled';
end;
$function$;

create or replace function public.fulus_api_record_expense(
  target_user_id uuid, target_business_id uuid, target_location_id uuid,
  target_amount numeric, target_category text, target_description text,
  target_operation_id text, target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy expense API wrapper is disabled';
end;
$function$;

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(
  target_user_id uuid, target_business_id uuid, target_shift_id uuid,
  target_closing_cash numeric, target_cash_difference numeric,
  target_closing_note text, target_closed_at timestamptz,
  target_operation_id text, target_device_id uuid
) returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy cash drawer API wrapper is disabled';
end;
$function$;

revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric
) from public,anon,authenticated,service_role;
revoke all on function public.fulus_api_create_customer(
  uuid,uuid,text,text,text,text,numeric,text
) from public,anon,authenticated,service_role;
revoke all on function public.fulus_api_update_customer(
  uuid,uuid,uuid,text,uuid,text,text,text,text,text,numeric,boolean,text
) from public,anon,authenticated,service_role;
revoke all on function public.fulus_api_update_expense(
  uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text
) from public,anon,authenticated,service_role;
revoke all on function public.fulus_api_record_expense(
  uuid,uuid,uuid,numeric,text,text,text,uuid
) from public,anon,authenticated,service_role;
revoke all on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid
) from public,anon,authenticated,service_role;

-- Legacy location RPC/trigger compatibility objects. These signatures are
-- referenced by later lockdown migrations but superseded by the actor-bound
-- location command path. Keep the objects defined and non-callable while the
-- fresh migration chain replays those historical hardening steps.
create or replace function public.fulus_api_create_location(
  target_user_id uuid,
  target_business_id uuid,
  target_operation_id text,
  target_name text,
  target_code text,
  target_address text,
  target_timezone text,
  target_request_hash text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy location API wrapper is disabled';
end;
$function$;

revoke all on function public.fulus_api_create_location(
  uuid,uuid,text,text,text,text,text,text
) from public, anon, authenticated, service_role;

create or replace function public.create_location(
  target_business_id uuid,
  target_operation_id text,
  target_name text,
  target_code text,
  target_address text,
  target_timezone text
) returns jsonb
language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode='42883', message='Legacy location RPC is disabled';
end;
$function$;

revoke all on function public.create_location(
  uuid,text,text,text,text,text
) from public, anon, authenticated, service_role;

create or replace function public.emit_location_sync_change()
returns trigger
language plpgsql security definer set search_path = ''
as $function$
begin
  return new;
end;
$function$;

revoke all on function public.emit_location_sync_change()
  from public, anon, authenticated, service_role;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  sku text not null,
  barcode text,
  category_id uuid references public.categories(id) on delete set null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  cost_price numeric not null default 0 check (cost_price >= 0),
  selling_price numeric not null default 0 check (selling_price >= 0),
  low_stock_threshold integer not null default 10 check (low_stock_threshold >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  tracks_stock boolean not null default true
);

create table if not exists public.product_stock_levels (
  product_id uuid not null references public.products(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete cascade,
  current_stock integer not null default 0 check (current_stock >= 0),
  updated_at timestamptz not null default now(),
  primary key (product_id, location_id)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  phone text,
  email text,
  address text,
  credit_limit numeric not null default 0 check (credit_limit >= 0),
  outstanding_balance numeric not null default 0 check (outstanding_balance >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text,
  unique (business_id, id)
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid not null references public.locations(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete restrict,
  cashier_user_id uuid references auth.users(id) on delete set null,
  client_reference text not null,
  invoice_number text not null,
  sale_date timestamptz not null default now(),
  subtotal numeric not null check (subtotal >= 0),
  discount numeric not null default 0 check (discount >= 0),
  tax numeric not null default 0 check (tax >= 0),
  total numeric not null check (total >= 0),
  amount_paid numeric not null default 0 check (amount_paid >= 0),
  payment_method text,
  notes text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, client_reference),
  unique (business_id, invoice_number)
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_price numeric not null check (unit_price >= 0),
  cost_price_at_sale numeric not null check (cost_price_at_sale >= 0),
  line_total numeric generated always as ((quantity)::numeric * unit_price) stored,
  description text not null default ''
);

create table if not exists public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  amount numeric not null check (amount > 0),
  payment_method text not null,
  operation_id text not null,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);

create table if not exists public.customer_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  sale_id uuid references public.sales(id) on delete restrict,
  entry_type text not null check (
    entry_type in ('credit_sale', 'repayment', 'adjustment', 'credit_reversal')
  ),
  amount numeric not null check (amount > 0),
  operation_id text not null,
  payment_method text,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  location_id uuid not null references public.locations(id) on delete restrict,
  quantity_delta integer not null check (quantity_delta <> 0),
  reason text not null check (length(trim(reason)) > 0),
  operation_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);

create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete restrict,
  client_reference text not null,
  refund_amount numeric not null default 0 check (refund_amount >= 0),
  reason text not null,
  status text not null default 'completed'
    check (status in ('completed', 'cancelled')),
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, client_reference)
);

create table if not exists public.return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references public.returns(id) on delete cascade,
  sale_item_id uuid not null references public.sale_items(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  amount numeric not null check (amount >= 0)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid references public.locations(id) on delete restrict,
  amount numeric not null check (amount > 0),
  category text not null,
  description text,
  operation_id text not null,
  expense_date timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  payment_method text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, operation_id)
);

create table if not exists public.cash_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  location_id uuid references public.locations(id) on delete restrict,
  entry_type text not null check (
    entry_type in ('opening', 'sale', 'expense', 'repayment', 'refund', 'adjustment')
  ),
  amount numeric not null check (amount >= 0),
  direction text not null check (direction in ('in', 'out')),
  reference_id uuid,
  operation_id text not null,
  created_by uuid references auth.users(id) on delete set null,
  device_id uuid references public.devices(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (business_id, operation_id)
);
