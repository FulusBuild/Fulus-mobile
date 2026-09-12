-- Fulus Phase 4 — catalog API authorization and performance indexes

create or replace function public.user_has_permission(
  target_business_id uuid,
  target_user_id uuid,
  target_permission text
)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.role_permissions rp on rp.role_id = bm.role_id
    join public.permissions p on p.id = rp.permission_id
    where bm.business_id = target_business_id
      and bm.user_id = target_user_id
      and bm.status = 'active'
      and p.code = target_permission
  );
$$;

revoke execute on function public.user_has_permission(uuid,uuid,text) from public,anon,authenticated;

create index if not exists products_business_category_idx on public.products(business_id,category_id);
create index if not exists products_business_supplier_idx on public.products(business_id,supplier_id);
create index if not exists product_stock_levels_location_idx on public.product_stock_levels(location_id);

-- Keep the API as the write boundary while preserving RLS as defense in depth.
drop policy if exists categories_manage_catalog on public.categories;
create policy categories_manage_catalog on public.categories for insert
with check ((select public.has_permission(business_id,'catalog.manage')));
create policy categories_update_catalog on public.categories for update
using ((select public.has_permission(business_id,'catalog.manage')))
with check ((select public.has_permission(business_id,'catalog.manage')));

drop policy if exists suppliers_manage_catalog on public.suppliers;
create policy suppliers_manage_catalog on public.suppliers for insert
with check ((select public.has_permission(business_id,'catalog.manage')));
create policy suppliers_update_catalog on public.suppliers for update
using ((select public.has_permission(business_id,'catalog.manage')))
with check ((select public.has_permission(business_id,'catalog.manage')));

drop policy if exists products_manage_catalog on public.products;
create policy products_manage_catalog on public.products for insert
with check ((select public.has_permission(business_id,'catalog.manage')));
create policy products_update_catalog on public.products for update
using ((select public.has_permission(business_id,'catalog.manage')))
with check ((select public.has_permission(business_id,'catalog.manage')));

create index if not exists audit_events_actor_idx on public.audit_events(actor_user_id);
create index if not exists audit_events_business_device_idx on public.audit_events(business_id,device_id);
create index if not exists audit_events_business_location_idx on public.audit_events(business_id,location_id);
create index if not exists business_memberships_business_role_idx on public.business_memberships(business_id,role_id);
create index if not exists devices_registered_by_idx on public.devices(registered_by);
create index if not exists idempotency_keys_business_device_idx on public.idempotency_keys(business_id,device_id);
create index if not exists idempotency_keys_user_idx on public.idempotency_keys(user_id);
create index if not exists location_memberships_business_location_idx on public.location_memberships(business_id,location_id);
create index if not exists role_permissions_permission_idx on public.role_permissions(permission_id);
create index if not exists sync_operations_user_idx on public.sync_operations(user_id);
