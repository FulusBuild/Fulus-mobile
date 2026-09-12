-- Fulus Backend — Phase 4 foundation security
-- Identity bootstrap, tenant bootstrap, catalog RLS and server-owned mutation boundaries.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.phone
  )
  on conflict (id) do update
    set full_name = coalesce(excluded.full_name, public.profiles.full_name),
        phone = coalesce(excluded.phone, public.profiles.phone),
        updated_at = now();
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.create_business_for_user(
  target_name text,
  target_currency_code text default 'NGN',
  target_timezone text default 'Africa/Lagos',
  target_location_name text default 'Main'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  new_business_id uuid;
  new_owner_role_id uuid;
  new_admin_role_id uuid;
  new_manager_role_id uuid;
  new_cashier_role_id uuid;
  new_location_id uuid;
begin
  if actor is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if target_name is null or length(trim(target_name)) < 2 then
    raise exception using errcode = '22023', message = 'Business name must be at least 2 characters';
  end if;

  insert into public.businesses (name, currency_code, timezone)
  values (trim(target_name), upper(trim(target_currency_code)), trim(target_timezone))
  returning id into new_business_id;

  insert into public.roles (business_id, name, description, is_system)
  values
    (new_business_id, 'owner', 'Business owner', true),
    (new_business_id, 'admin', 'Business administrator', true),
    (new_business_id, 'manager', 'Business manager', true),
    (new_business_id, 'cashier', 'Sales/cashier role', true)
  returning id into new_owner_role_id;

  select r.id into new_admin_role_id from public.roles r
    where r.business_id = new_business_id and r.name = 'admin';
  select r.id into new_manager_role_id from public.roles r
    where r.business_id = new_business_id and r.name = 'manager';
  select r.id into new_cashier_role_id from public.roles r
    where r.business_id = new_business_id and r.name = 'cashier';

  insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
  values (new_business_id, actor, new_owner_role_id, 'active', now());

  insert into public.locations (business_id, name)
  values (new_business_id, coalesce(nullif(trim(target_location_name), ''), 'Main'))
  returning id into new_location_id;

  insert into public.location_memberships (business_id, location_id, user_id, status)
  values (new_business_id, new_location_id, actor, 'active');

  insert into public.role_permissions (role_id, permission_id)
  select new_owner_role_id, p.id from public.permissions p
  on conflict do nothing;

  insert into public.role_permissions (role_id, permission_id)
  select new_admin_role_id, p.id from public.permissions p
  where p.code <> 'audit.read'
  on conflict do nothing;

  insert into public.role_permissions (role_id, permission_id)
  select new_manager_role_id, p.id from public.permissions p
  where p.code in (
    'business.read','locations.read','employees.read','catalog.read',
    'inventory.read','inventory.adjust','sales.read','sales.create',
    'returns.create','customers.read','customers.manage','credit.manage',
    'cash.read','cash.manage','finance.read','reports.read'
  )
  on conflict do nothing;

  insert into public.role_permissions (role_id, permission_id)
  select new_cashier_role_id, p.id from public.permissions p
  where p.code in (
    'business.read','locations.read','catalog.read','inventory.read',
    'sales.read','sales.create','customers.read','credit.manage','cash.read'
  )
  on conflict do nothing;

  return jsonb_build_object(
    'business_id', new_business_id,
    'owner_role_id', new_owner_role_id,
    'admin_role_id', new_admin_role_id,
    'manager_role_id', new_manager_role_id,
    'cashier_role_id', new_cashier_role_id,
    'location_id', new_location_id
  );
end;
$$;

revoke execute on function public.create_business_for_user(text,text,text,text)
from public, anon, authenticated;

revoke execute on function public._fulus_catalog_change(uuid,text,uuid,text,jsonb)
from public, anon, authenticated;
revoke execute on function public.accept_sync_operation(uuid,uuid,uuid,text,text,text,text,jsonb)
from public, anon, authenticated;

drop policy if exists categories_select_member on public.categories;
drop policy if exists categories_manage_admin on public.categories;
create policy categories_select_member on public.categories for select
using ((select public.has_permission(business_id, 'catalog.read')));
create policy categories_manage_catalog on public.categories for all
using ((select public.has_permission(business_id, 'catalog.manage')))
with check ((select public.has_permission(business_id, 'catalog.manage')));

drop policy if exists suppliers_select_member on public.suppliers;
drop policy if exists suppliers_manage_admin on public.suppliers;
create policy suppliers_select_member on public.suppliers for select
using ((select public.has_permission(business_id, 'catalog.read')));
create policy suppliers_manage_catalog on public.suppliers for all
using ((select public.has_permission(business_id, 'catalog.manage')))
with check ((select public.has_permission(business_id, 'catalog.manage')));

drop policy if exists products_select_member on public.products;
drop policy if exists products_manage_admin on public.products;
create policy products_select_member on public.products for select
using ((select public.has_permission(business_id, 'catalog.read')));
create policy products_manage_catalog on public.products for all
using ((select public.has_permission(business_id, 'catalog.manage')))
with check ((select public.has_permission(business_id, 'catalog.manage')));

drop policy if exists product_stock_levels_select_member on public.product_stock_levels;
create policy product_stock_levels_select_member on public.product_stock_levels for select
using (
  (select public.has_permission(
    (select p.business_id from public.products p where p.id = product_stock_levels.product_id),
    'inventory.read'
  ))
);

revoke insert, update, delete on public.product_stock_levels from anon, authenticated;
revoke insert, update, delete on public.categories from anon, authenticated;
revoke insert, update, delete on public.suppliers from anon, authenticated;
revoke insert, update, delete on public.products from anon, authenticated;

grant select on public.categories, public.suppliers, public.products, public.product_stock_levels to authenticated;

create index if not exists products_business_sku_idx
  on public.products (business_id, sku);
create index if not exists products_business_barcode_idx
  on public.products (business_id, barcode)
  where barcode is not null;

create or replace function public.catalog_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists categories_set_updated_at on public.categories;
create trigger categories_set_updated_at before update on public.categories
for each row execute function public.catalog_set_updated_at();

drop trigger if exists suppliers_set_updated_at on public.suppliers;
create trigger suppliers_set_updated_at before update on public.suppliers
for each row execute function public.catalog_set_updated_at();

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
for each row execute function public.catalog_set_updated_at();

create or replace function public._fulus_append_change(
  target_business_id uuid,
  target_entity_type text,
  target_entity_id uuid,
  target_operation text,
  target_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_sequence bigint;
begin
  if target_operation not in ('upsert','delete') then
    raise exception using errcode='22023', message='Invalid change operation';
  end if;

  insert into public.sync_changes(
    business_id, entity_type, entity_id, operation, payload
  )
  values (
    target_business_id, target_entity_type, target_entity_id,
    target_operation, target_payload
  )
  returning sequence into new_sequence;

  return new_sequence;
end;
$$;

revoke execute on function public._fulus_append_change(uuid,text,uuid,text,jsonb)
from public, anon, authenticated;
