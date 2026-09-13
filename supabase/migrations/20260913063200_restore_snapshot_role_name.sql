create or replace function public.build_fulus_restore_snapshot(p_business_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot jsonb;
begin
  if p_business_id is null or p_user_id is null then
    raise exception using errcode = '22023', message = 'business_id and user_id are required';
  end if;

  with authz as (
    select bm.business_id, bm.user_id, bm.role_id, bm.status,
           bm.joined_at, bm.created_at, bm.updated_at, r.name as role_name
    from public.business_memberships bm
    left join public.roles r on r.id = bm.role_id
    where bm.business_id = p_business_id
      and bm.user_id = p_user_id
      and bm.status = 'active'
      and r.name in ('owner', 'admin')
    limit 1
  )
  select jsonb_build_object(
    'version', 6,
    'generated_at', now(),
    'business', to_jsonb(b),
    'businesses', jsonb_build_array(to_jsonb(b)),
    'membership', jsonb_build_object(
      'business_id', a.business_id, 'user_id', a.user_id,
      'role_id', a.role_id, 'role_name', a.role_name, 'status', a.status,
      'joined_at', a.joined_at, 'created_at', a.created_at, 'updated_at', a.updated_at
    ),
    'profile', coalesce(to_jsonb(p), 'null'::jsonb),
    'locations', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.locations t where t.business_id = p_business_id), '[]'::jsonb),
    'location_memberships', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.location_memberships t where t.business_id = p_business_id), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.products t where t.business_id = p_business_id), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.categories t where t.business_id = p_business_id), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.suppliers t where t.business_id = p_business_id), '[]'::jsonb),
    'customers', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.customers t where t.business_id = p_business_id), '[]'::jsonb),
    'sales', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.sales t where t.business_id = p_business_id), '[]'::jsonb),
    'inventory_movements', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.inventory_movements t where t.business_id = p_business_id), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.expenses t where t.business_id = p_business_id), '[]'::jsonb),
    'income_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.income_records t where t.business_id = p_business_id), '[]'::jsonb),
    'expense_categories', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.expense_categories t where t.business_id = p_business_id), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.returns t where t.business_id = p_business_id), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.devices t where t.business_id = p_business_id), '[]'::jsonb),
    'audit_events', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.audit_events t where t.business_id = p_business_id), '[]'::jsonb),
    'cash_ledger', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.cash_ledger t where t.business_id = p_business_id), '[]'::jsonb),
    'tax_remittances', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.tax_remittances t where t.business_id = p_business_id), '[]'::jsonb),
    'cash_drawer_shifts', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.cash_drawer_shifts t where t.business_id = p_business_id), '[]'::jsonb),
    'staff_invites', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.staff_invites t where t.business_id = p_business_id), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.roles t where t.business_id = p_business_id), '[]'::jsonb),
    'business_memberships', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.business_memberships t where t.business_id = p_business_id), '[]'::jsonb),
    'profiles', coalesce((select jsonb_agg(to_jsonb(px) order by px.id) from public.profiles px where px.id in (select bm.user_id from public.business_memberships bm where bm.business_id = p_business_id)), '[]'::jsonb),
    'product_stock_levels', coalesce((select jsonb_agg(to_jsonb(t) order by t.product_id, t.location_id) from public.product_stock_levels t where t.product_id in (select id from public.products where business_id = p_business_id)), '[]'::jsonb),
    'sale_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.sale_items t where t.sale_id in (select id from public.sales where business_id = p_business_id)), '[]'::jsonb),
    'sale_payments', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.sale_payments t where t.sale_id in (select id from public.sales where business_id = p_business_id)), '[]'::jsonb),
    'return_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.return_items t where t.return_id in (select id from public.returns where business_id = p_business_id)), '[]'::jsonb),
    'customer_ledger_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.customer_ledger_entries t where t.customer_id in (select id from public.customers where business_id = p_business_id)), '[]'::jsonb),
    'supplier_ledger_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.supplier_ledger_entries t where t.supplier_id in (select id from public.suppliers where business_id = p_business_id)), '[]'::jsonb),
    'role_permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.role_permissions t where t.role_id in (select id from public.roles where business_id = p_business_id)), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.permissions t where t.id in (select distinct rp.permission_id from public.role_permissions rp where rp.role_id in (select id from public.roles where business_id = p_business_id))), '[]'::jsonb),
    'local_restore_notes', jsonb_build_object(
      'non_cloud_local_tables', jsonb_build_array('app_notifications','paired_printers','diagnostic_events','sync_queue_items','draft_carts','draft_cart_items','draft_cart_payments'),
      'employee_source', 'business_memberships + profiles',
      'authorization_source', 'roles + role_permissions + permissions',
      'version', 6,
      'snapshot_consistency', 'single PostgreSQL SELECT statement snapshot'
    )
  ) into v_snapshot
  from authz a
  join public.businesses b on b.id = a.business_id
  left join public.profiles p on p.id = a.user_id;

  if v_snapshot is null then
    raise exception using errcode = '42501', message = 'Restore is not authorized for this business';
  end if;

  return v_snapshot;
end;
$$;

revoke all on function public.build_fulus_restore_snapshot(uuid, uuid) from public;
grant execute on function public.build_fulus_restore_snapshot(uuid, uuid) to service_role;
