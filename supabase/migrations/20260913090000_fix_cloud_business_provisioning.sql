-- Fix cloud business provisioning when called from the service-role Edge Function.
-- The previous RPC relied on auth.uid(), but the Edge Function authenticates
-- the bearer token itself and then calls Postgres with the service-role client.
-- This RPC accepts the already-authenticated user id explicitly and creates
-- the owner role separately so INSERT ... RETURNING cannot produce multiple rows.

create or replace function public.create_business_for_user_service(
  target_user_id uuid,
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
  new_business_id uuid;
  new_owner_role_id uuid;
  new_admin_role_id uuid;
  new_manager_role_id uuid;
  new_cashier_role_id uuid;
  new_location_id uuid;
begin
  if target_user_id is null then
    raise exception using errcode='42501', message='User is required';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception using errcode='22023', message='User account not found';
  end if;
  if exists (select 1 from public.business_memberships where user_id = target_user_id) then
    raise exception using errcode='23505', message='This Fulus Cloud account is already linked to a business. One cloud account can own only one business.';
  end if;
  if target_name is null or length(trim(target_name)) < 2 then
    raise exception using errcode='22023', message='Business name must be at least 2 characters';
  end if;

  insert into public.businesses (name, currency_code, timezone)
  values (trim(target_name), upper(trim(target_currency_code)), trim(target_timezone))
  returning id into new_business_id;

  insert into public.roles (business_id, name, description, is_system)
  values (new_business_id, 'owner', 'Business owner', true)
  returning id into new_owner_role_id;

  insert into public.roles (business_id, name, description, is_system)
  values
    (new_business_id, 'admin', 'Business administrator', true),
    (new_business_id, 'manager', 'Business manager', true),
    (new_business_id, 'cashier', 'Sales/cashier role', true);

  select r.id into new_admin_role_id from public.roles r
  where r.business_id = new_business_id and r.name = 'admin';
  select r.id into new_manager_role_id from public.roles r
  where r.business_id = new_business_id and r.name = 'manager';
  select r.id into new_cashier_role_id from public.roles r
  where r.business_id = new_business_id and r.name = 'cashier';

  insert into public.business_memberships (business_id, user_id, role_id, status, joined_at)
  values (new_business_id, target_user_id, new_owner_role_id, 'active', now());

  insert into public.locations (business_id, name)
  values (new_business_id, coalesce(nullif(trim(target_location_name), ''), 'Main'))
  returning id into new_location_id;

  insert into public.location_memberships (business_id, location_id, user_id, status)
  values (new_business_id, new_location_id, target_user_id, 'active');

  insert into public.role_permissions (role_id, permission_id)
  select new_owner_role_id, p.id from public.permissions p on conflict do nothing;
  insert into public.role_permissions (role_id, permission_id)
  select new_admin_role_id, p.id from public.permissions p
  where p.code <> 'audit.read' on conflict do nothing;
  insert into public.role_permissions (role_id, permission_id)
  select new_manager_role_id, p.id from public.permissions p
  where p.code in (
    'business.read','locations.read','employees.read','catalog.read',
    'inventory.read','inventory.adjust','sales.read','sales.create',
    'returns.create','customers.read','customers.manage','credit.manage',
    'cash.read','cash.manage','finance.read','reports.read'
  ) on conflict do nothing;
  insert into public.role_permissions (role_id, permission_id)
  select new_cashier_role_id, p.id from public.permissions p
  where p.code in (
    'business.read','locations.read','catalog.read','inventory.read',
    'sales.read','sales.create','customers.read','credit.manage','cash.read'
  ) on conflict do nothing;

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

revoke all on function public.create_business_for_user_service(uuid,text,text,text,text)
from public, anon, authenticated;
grant execute on function public.create_business_for_user_service(uuid,text,text,text,text)
to service_role;
