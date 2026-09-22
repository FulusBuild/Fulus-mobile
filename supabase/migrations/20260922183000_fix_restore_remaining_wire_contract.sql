-- Cloud Sync V1: close remaining restore snapshot wire-contract gaps
-- discovered by comparing every imported local table with the production
-- PostgreSQL representation. This migration is additive to the inventory
-- movement contract migration immediately before it.
-- Cloud Sync V1: align the server inventory movement wire contract with
-- the mobile restore/canonical-reconciliation schema.
--
-- The authoritative PostgreSQL ledger stores quantity_delta, while mobile
-- stores the richer movement vocabulary. The server translates that contract
-- at the restore/change-feed boundary. Existing idempotency response bodies
-- preserve the authoritative post-command stock for absolute adjustments.
--
-- The normalized inventory_movements table remains unchanged.

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
    'version', 6,
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
    'roles', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.roles t where t.business_id = p_business_id), '[]'::jsonb),
    'business_memberships', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.business_memberships t where t.business_id = p_business_id), '[]'::jsonb),
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
    'permissions', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.permissions t where t.id in (select distinct rp.permission_id from public.role_permissions rp where rp.role_id in (select id from public.roles where business_id = p_business_id))), '[]'::jsonb),
    'local_restore_notes', jsonb_build_object(
      'non_cloud_local_tables', jsonb_build_array('app_notifications','paired_printers','diagnostic_events','sync_queue_items','draft_carts','draft_cart_items','draft_cart_payments'),
      'server_schema_optional_sections_omitted', jsonb_build_array('supplier_ledger_entries','tax_remittances'),
      'employee_source', 'business_memberships + profiles',
      'authorization_source', 'roles + role_permissions + permissions',
      'version', 6,
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

CREATE OR REPLACE FUNCTION public.apply_inventory_adjustment(target_business_id uuid, target_product_id uuid, target_location_id uuid, target_quantity_delta integer, target_reason text, target_operation_id text, target_device_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
  new_stock integer;
  movement_id uuid;
  existing_delta integer;
  existing_reason text;
begin
  if actor is null then raise exception using errcode='42501', message='Authentication required'; end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then raise exception using errcode='22023', message='operation_id is required'; end if;
  if target_quantity_delta = 0 then raise exception using errcode='22023', message='Quantity delta cannot be zero'; end if;
  if not public.has_permission(target_business_id,'inventory.adjust') then raise exception using errcode='42501', message='Inventory adjustment permission required'; end if;
  if target_device_id is not null and not exists(select 1 from public.devices d where d.id=target_device_id and d.business_id=target_business_id and d.status='active') then raise exception using errcode='42501', message='Device is not active for this business'; end if;
  if not exists(select 1 from public.products p where p.id=target_product_id and p.business_id=target_business_id and p.deleted_at is null) then raise exception using errcode='22023', message='Product does not belong to business'; end if;
  if not exists(select 1 from public.locations l where l.id=target_location_id and l.business_id=target_business_id) then raise exception using errcode='22023', message='Location does not belong to business'; end if;

  request_hash := md5(jsonb_build_object('business_id',target_business_id,'product_id',target_product_id,'location_id',target_location_id,'quantity_delta',target_quantity_delta,'reason',trim(target_reason),'device_id',target_device_id)::text);

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,actor,target_operation_id,'inventory.adjust',request_hash)
  on conflict(business_id,key) do nothing;

  select * into idem from public.idempotency_keys ik
  where ik.business_id=target_business_id and ik.key=target_operation_id for update;

  if idem.operation_type <> 'inventory.adjust' or idem.request_hash <> request_hash then
    raise exception using errcode='P0009', message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;

  insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
  values(target_business_id,target_product_id,target_location_id,target_quantity_delta,trim(target_reason),target_operation_id,actor,target_device_id)
  on conflict (business_id,operation_id) do nothing
  returning id into movement_id;

  if movement_id is null then
    select im.id, im.quantity_delta, im.reason into movement_id, existing_delta, existing_reason
    from public.inventory_movements im
    where im.business_id=target_business_id and im.operation_id=target_operation_id for update;
    if existing_delta <> target_quantity_delta or coalesce(existing_reason,'') <> coalesce(trim(target_reason),'') then
      raise exception using errcode='P0009', message='Operation id was already used with a different request';
    end if;
    select current_stock into new_stock from public.product_stock_levels
    where product_id=target_product_id and location_id=target_location_id;
    result := jsonb_build_object('status','already_applied','movement_id',movement_id,'current_stock',coalesce(new_stock,0),'server_authoritative',true);
    update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
    return result;
  end if;

  insert into public.product_stock_levels(product_id,location_id,current_stock,updated_at)
  values(target_product_id,target_location_id,0,now())
  on conflict(product_id,location_id) do nothing;

  update public.product_stock_levels
  set current_stock=current_stock + target_quantity_delta, updated_at=now()
  where product_id=target_product_id and location_id=target_location_id and current_stock + target_quantity_delta >= 0
  returning current_stock into new_stock;
  if not found then raise exception using errcode='22013',message='Inventory cannot become negative'; end if;

  perform public._fulus_append_change(target_business_id,'inventory_movement',movement_id,'upsert',
    jsonb_build_object('id',movement_id,'product_id',target_product_id,'location_id',target_location_id,'quantity_delta',target_quantity_delta,'quantity',null,'new_quantity',null,'movement_type','adjustment','reason',trim(target_reason),'current_stock',new_stock));

  result := jsonb_build_object('status','applied','movement_id',movement_id,'current_stock',new_stock,'server_authoritative',true);
  update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_inventory_quantity(target_business_id uuid, target_product_id uuid, target_location_id uuid, target_new_quantity integer, target_reason text, target_operation_id text, target_device_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  product_business_id uuid;
  tracks_stock boolean;
  current_quantity integer;
  quantity_delta integer;
  movement_id uuid;
  actor uuid := auth.uid();
  idem public.idempotency_keys%rowtype;
  request_hash text;
  result jsonb;
begin
  if target_new_quantity < 0 then raise exception using errcode = '22023', message = 'Stock quantity cannot be negative'; end if;
  if actor is null then raise exception using errcode = '42501', message = 'Authentication required'; end if;
  if target_operation_id is null or length(trim(target_operation_id)) = 0 then raise exception using errcode = '22023', message = 'operation_id is required'; end if;
  if not exists (select 1 from public.business_memberships where business_id = target_business_id and user_id = actor and status = 'active') then raise exception using errcode = '42501', message = 'User is not an active member of this business'; end if;
  if not exists (select 1 from public.devices where id = target_device_id and business_id = target_business_id and status = 'active') then raise exception using errcode = '42501', message = 'Device is not registered or active'; end if;

  request_hash := md5(jsonb_build_object('business_id',target_business_id,'product_id',target_product_id,'location_id',target_location_id,'new_quantity',target_new_quantity,'reason',trim(target_reason),'device_id',target_device_id)::text);

  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash)
  values(target_business_id,target_device_id,actor,target_operation_id,'inventory.set',request_hash)
  on conflict(business_id,key) do nothing;

  select * into idem from public.idempotency_keys ik
  where ik.business_id=target_business_id and ik.key=target_operation_id for update;

  if idem.operation_type <> 'inventory.set' or idem.request_hash <> request_hash then
    raise exception using errcode='P0009', message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;

  select p.business_id, p.tracks_stock into product_business_id, tracks_stock
  from public.products p where p.id = target_product_id for update;
  if product_business_id is null or product_business_id <> target_business_id then raise exception using errcode = 'P0002', message = 'Product does not belong to this business'; end if;
  if not coalesce(tracks_stock, false) then raise exception using errcode = '22023', message = 'Product does not track stock'; end if;
  if not exists (select 1 from public.locations where id = target_location_id and business_id = target_business_id) then raise exception using errcode = 'P0002', message = 'Location does not belong to this business'; end if;

  insert into public.product_stock_levels(product_id,location_id,current_stock,updated_at)
  values (target_product_id,target_location_id,0,now())
  on conflict (product_id,location_id) do nothing;

  select coalesce(ps.current_stock,0) into current_quantity
  from public.product_stock_levels ps
  where ps.product_id=target_product_id and ps.location_id=target_location_id for update;

  quantity_delta := target_new_quantity - coalesce(current_quantity,0);
  if quantity_delta = 0 then
    result := jsonb_build_object('status','already_applied','current_stock',current_quantity,'server_authoritative',true);
    update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
    return result;
  end if;

  insert into public.inventory_movements(business_id,product_id,location_id,quantity_delta,reason,operation_id,user_id,device_id)
  values(target_business_id,target_product_id,target_location_id,quantity_delta,trim(target_reason),target_operation_id,actor,target_device_id)
  returning id into movement_id;

  update public.product_stock_levels
  set current_stock=target_new_quantity,updated_at=now()
  where product_id=target_product_id and location_id=target_location_id;
  if not found then raise exception using errcode = 'P0002', message = 'Stock level row disappeared during absolute adjustment'; end if;

  perform public._fulus_append_change(target_business_id,'inventory_movement',movement_id,'upsert',
    jsonb_build_object('id',movement_id,'product_id',target_product_id,'location_id',target_location_id,'quantity_delta',quantity_delta,'quantity',null,'new_quantity',target_new_quantity,'movement_type','adjustment','reason',trim(target_reason),'current_stock',target_new_quantity));

  result := jsonb_build_object('status','applied','movement_id',movement_id,'current_stock',target_new_quantity,'server_authoritative',true);
  update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
  return result;
end;
$function$;
