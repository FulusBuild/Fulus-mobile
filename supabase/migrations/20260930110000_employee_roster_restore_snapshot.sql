-- Include the cloud employee roster in authoritative restore snapshots.
-- Employee rows created before the snapshot boundary must be present in the
-- snapshot itself; otherwise the post-boundary delta pull cannot reconstruct
-- them on a fresh device.
CREATE OR REPLACE FUNCTION public.build_fulus_restore_snapshot(p_business_id uuid, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'version', 7,
    'generated_at', now(),
    'sync_boundary', coalesce((select max(sequence) from public.sync_changes where business_id = p_business_id), 0),
    'business', to_jsonb(b),
    'businesses', jsonb_build_array(to_jsonb(b)),
    'membership', jsonb_build_object(
      'business_id', a.business_id, 'user_id', a.user_id,
      'role_id', a.role_id, 'status', a.status, 'joined_at', a.joined_at,
      'created_at', a.created_at, 'updated_at', a.updated_at, 'role_name', a.role_name
    ),
    'profile', coalesce(to_jsonb(p), 'null'::jsonb),
    'locations', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.locations t where t.business_id = p_business_id), '[]'::jsonb),
    'location_memberships', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.location_memberships t where t.business_id = p_business_id), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.products t where t.business_id = p_business_id), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.categories t where t.business_id = p_business_id), '[]'::jsonb),
    'expense_categories', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.expense_categories t where t.business_id = p_business_id), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.suppliers t where t.business_id = p_business_id), '[]'::jsonb),
    'customers', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.customers t where t.business_id = p_business_id), '[]'::jsonb),
    'sales', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.sales t where t.business_id = p_business_id), '[]'::jsonb),
    'inventory_movements', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'business_id', t.business_id,
          'product_id', t.product_id,
          'location_id', t.location_id,
          'quantity_delta', t.quantity_delta,
          'quantity', case
            when coalesce(ik.operation_type, '') in ('inventory.set', 'inventory.adjust') then null
            else abs(t.quantity_delta)
          end,
          'new_quantity', case
            when coalesce(ik.operation_type, '') in ('inventory.set', 'inventory.adjust')
              then nullif(ik.response_body->>'current_stock', '')::integer
            else null
          end,
          'movement_type', case
            when ik.operation_type in ('inventory.set', 'inventory.adjust') then 'adjustment'
            when lower(coalesce(t.reason, '')) like 'sale %' then 'sale'
            when t.quantity_delta > 0 then 'in'
            when t.quantity_delta < 0 then 'out'
            else 'adjustment'
          end,
          'reason', t.reason,
          'operation_id', t.operation_id,
          'user_id', t.user_id,
          'device_id', t.device_id,
          'created_at', t.created_at,
          'updated_at', t.created_at
        ) order by t.id
      )
      from public.inventory_movements t
      left join public.idempotency_keys ik
        on ik.business_id = t.business_id and ik.key = t.operation_id
      where t.business_id = p_business_id
    ), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'business_id', t.business_id,
          'location_id', coalesce(
            t.location_id,
            (
              select cl.location_id
              from public.cash_ledger cl
              where cl.business_id = t.business_id
                and cl.reference_id = t.id
                and cl.entry_type = 'expense'
              order by cl.created_at desc
              limit 1
            ),
            (
              select l.id
              from public.locations l
              where l.business_id = p_business_id and l.status = 'active'
              order by l.created_at, l.id
              limit 1
            )
          ),
          'amount', t.amount,
          'category', t.category,
          'description', coalesce(t.description, ''),
          'operation_id', t.operation_id,
          'expense_date', t.expense_date,
          'created_by', t.created_by,
          'device_id', t.device_id,
          'payment_method', t.payment_method,
          'created_at', t.expense_date,
          'updated_at', t.expense_date
        ) order by t.id
      )
      from public.expenses t
      where t.business_id = p_business_id
    ), '[]'::jsonb),
    'income_records', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.income_records t where t.business_id = p_business_id), '[]'::jsonb),
    'returns', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'business_id', t.business_id,
          'sale_id', t.sale_id,
          'customer_id', t.customer_id,
          'client_reference', t.client_reference,
          'refund_amount', t.refund_amount,
          'reason', t.reason,
          'return_reason', t.reason,
          'refund_method', 'cash',
          'status', t.status,
          'inventory_restored', t.status = 'completed',
          'is_void', false,
          'completed_at', case when t.status = 'completed' then t.created_at else null end,
          'created_by', t.created_by,
          'device_id', t.device_id,
          'created_at', t.created_at,
          'updated_at', t.created_at
        ) order by t.id
      )
      from public.returns t
      where t.business_id = p_business_id
    ), '[]'::jsonb),
    'devices', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.devices t where t.business_id = p_business_id), '[]'::jsonb),
    'audit_events', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.audit_events t where t.business_id = p_business_id), '[]'::jsonb),
    'cash_ledger', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.cash_ledger t where t.business_id = p_business_id), '[]'::jsonb),
    'cash_drawer_shifts', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.cash_drawer_shifts t where t.business_id = p_business_id), '[]'::jsonb),
    'staff_invites', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.staff_invites t where t.business_id = p_business_id), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.employees t where t.business_id = p_business_id), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.roles t where t.business_id = p_business_id), '[]'::jsonb),
    'business_memberships', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.business_memberships t where t.business_id = p_business_id), '[]'::jsonb),
    'business_member_permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id, t.permission_id) from public.business_member_permissions t where t.business_id = p_business_id), '[]'::jsonb),
    'profiles', coalesce((select jsonb_agg(to_jsonb(px) order by px.id) from public.profiles px where px.id in (select bm.user_id from public.business_memberships bm where bm.business_id = p_business_id)), '[]'::jsonb),
    'product_stock_levels', coalesce((select jsonb_agg(to_jsonb(t) order by t.product_id, t.location_id) from public.product_stock_levels t where t.product_id in (select id from public.products where business_id = p_business_id)), '[]'::jsonb),
    'sale_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.sale_items t where t.sale_id in (select id from public.sales where business_id = p_business_id)), '[]'::jsonb),
    'sale_payments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'business_id', t.business_id,
          'sale_id', t.sale_id,
          'amount', t.amount,
          'payment_method', t.payment_method,
          'method', t.payment_method,
          'operation_id', t.operation_id,
          'created_by', t.created_by,
          'device_id', t.device_id,
          'created_at', t.created_at,
          'recorded_at', t.created_at
        ) order by t.id
      )
      from public.sale_payments t
      where t.sale_id in (select id from public.sales where business_id = p_business_id)
    ), '[]'::jsonb),
    'return_items', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.return_items t where t.return_id in (select id from public.returns where business_id = p_business_id)), '[]'::jsonb),
    'customer_ledger_entries', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.customer_ledger_entries t where t.customer_id in (select id from public.customers where business_id = p_business_id)), '[]'::jsonb),
    'role_permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.role_id, t.permission_id) from public.role_permissions t where t.role_id in (select id from public.roles where business_id = p_business_id)), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.permissions t), '[]'::jsonb),
    'local_restore_notes', jsonb_build_object(
      'non_cloud_local_tables', jsonb_build_array('app_notifications','paired_printers','diagnostic_events','sync_queue_items','draft_carts','draft_cart_items','draft_cart_payments'),
      'server_schema_optional_sections_omitted', jsonb_build_array('supplier_ledger_entries','tax_remittances'),
      'employee_source', 'employees + business_memberships + profiles',
      'authorization_source', 'roles + role_permissions + business_member_permissions + permissions',
      'version', 7,
      'snapshot_consistency', 'single PostgreSQL SELECT statement snapshot',
      'sync_boundary', 'max sync_changes.sequence for this business in the same statement snapshot'
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
$function$;

REVOKE ALL ON FUNCTION public.build_fulus_restore_snapshot(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.build_fulus_restore_snapshot(uuid, uuid) TO service_role;
