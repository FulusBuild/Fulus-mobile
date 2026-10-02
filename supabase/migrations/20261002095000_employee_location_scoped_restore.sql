-- Part 04: give non-admin employees a location-scoped bootstrap snapshot.
--
-- The existing build_fulus_restore_snapshot RPC is intentionally restricted
-- to owner/admin because its payload is a complete business image. Employee
-- provisioning must not reuse that payload: the employee's assigned location
-- is the isolation boundary for operational data.
CREATE OR REPLACE FUNCTION public.build_fulus_employee_restore_snapshot(
  p_business_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_snapshot jsonb;
  v_location_id uuid;
  v_membership record;
  v_employee record;
BEGIN
  IF p_business_id IS NULL OR p_user_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023',
      message = 'business_id and user_id are required';
  END IF;

  SELECT
    bm.business_id,
    bm.user_id,
    bm.role_id,
    bm.status,
    bm.joined_at,
    bm.created_at,
    bm.updated_at,
    r.name AS role_name
  INTO v_membership
  FROM public.business_memberships bm
  LEFT JOIN public.roles r ON r.id = bm.role_id
  WHERE bm.business_id = p_business_id
    AND bm.user_id = p_user_id
    AND bm.status = 'active'
  LIMIT 1;

  IF v_membership.business_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'Restore is not authorized for this business';
  END IF;

  IF v_membership.role_name IN ('owner', 'admin') THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'Administrator accounts must use the full business restore';
  END IF;

  SELECT e.*
  INTO v_employee
  FROM public.employees e
  WHERE e.business_id = p_business_id
    AND (e.cloud_user_id = p_user_id OR e.auth_user_id = p_user_id)
    AND e.is_active = true
    AND e.deleted_at IS NULL
  ORDER BY e.updated_at DESC, e.id
  LIMIT 1;

  v_location_id := v_employee.location_id;

  IF v_location_id IS NULL THEN
    SELECT lm.location_id
    INTO v_location_id
    FROM public.location_memberships lm
    WHERE lm.business_id = p_business_id
      AND lm.user_id = p_user_id
      AND lm.status = 'active'
    ORDER BY lm.created_at, lm.location_id
    LIMIT 1;
  END IF;

  IF v_location_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.locations l
    WHERE l.id = v_location_id
      AND l.business_id = p_business_id
      AND l.status = 'active'
  ) THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'Employee does not have an active business location';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.location_memberships lm
    WHERE lm.business_id = p_business_id
      AND lm.user_id = p_user_id
      AND lm.location_id = v_location_id
      AND lm.status = 'active'
  ) THEN
    RAISE EXCEPTION USING errcode = '42501',
      message = 'Employee is not an active member of the assigned location';
  END IF;

  SELECT jsonb_build_object(
    'version', 7,
    'generated_at', now(),
    'sync_boundary', coalesce(
      (SELECT max(sequence)
       FROM public.sync_changes sc
       WHERE sc.business_id = p_business_id),
      0
    ),
    'business', to_jsonb(b),
    'businesses', jsonb_build_array(to_jsonb(b)),
    'membership', jsonb_build_object(
      'business_id', v_membership.business_id,
      'user_id', v_membership.user_id,
      'role_id', v_membership.role_id,
      'status', v_membership.status,
      'joined_at', v_membership.joined_at,
      'created_at', v_membership.created_at,
      'updated_at', v_membership.updated_at,
      'role_name', v_membership.role_name
    ),
    'profile', coalesce(to_jsonb(p), 'null'::jsonb),

    -- Locations are strictly limited to the employee's active assignment.
    'locations', coalesce((
      SELECT jsonb_agg(to_jsonb(l) ORDER BY l.id)
      FROM public.locations l
      WHERE l.business_id = p_business_id
        AND l.id = v_location_id
        AND l.status = 'active'
    ), '[]'::jsonb),
    'location_memberships', coalesce((
      SELECT jsonb_agg(to_jsonb(lm) ORDER BY lm.id)
      FROM public.location_memberships lm
      WHERE lm.business_id = p_business_id
        AND lm.user_id = p_user_id
        AND lm.location_id = v_location_id
        AND lm.status = 'active'
    ), '[]'::jsonb),

    -- Catalog/customer identity is intentionally business-wide in Fulus.
    'products', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.products t
      WHERE t.business_id = p_business_id
    ), '[]'::jsonb),
    'categories', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.categories t
      WHERE t.business_id = p_business_id
    ), '[]'::jsonb),
    'suppliers', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.suppliers t
      WHERE t.business_id = p_business_id
    ), '[]'::jsonb),
    'customers', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.customers t
      WHERE t.business_id = p_business_id
    ), '[]'::jsonb),

    -- Operational history is restricted to the assigned location.
    'sales', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.sales t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),
    'sale_items', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.sale_items t
      WHERE t.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.business_id = p_business_id
          AND s.location_id = v_location_id
      )
    ), '[]'::jsonb),
    'sale_payments', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.sale_payments t
      WHERE t.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.business_id = p_business_id
          AND s.location_id = v_location_id
      )
    ), '[]'::jsonb),
    'product_stock_levels', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.product_id, t.location_id)
      FROM public.product_stock_levels t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),
    'inventory_movements', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.inventory_movements t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),
    'expenses', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.expenses t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),
    'income_records', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.income_records t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),
    'returns', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.returns t
      WHERE t.business_id = p_business_id
        AND t.sale_id IN (
          SELECT s.id FROM public.sales s
          WHERE s.business_id = p_business_id
            AND s.location_id = v_location_id
        )
    ), '[]'::jsonb),
    'customer_ledger_entries', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.customer_ledger_entries t
      WHERE t.business_id = p_business_id
    ), '[]'::jsonb),
    'cash_drawer_shifts', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.cash_drawer_shifts t
      WHERE t.business_id = p_business_id
        AND t.location_id = v_location_id
    ), '[]'::jsonb),

    -- Only the signed-in employee is projected into the fresh local staff
    -- identity set. Other staff identities are not part of the bootstrap
    -- payload, while historical sales still retain their cloud user IDs.
    'employees', coalesce((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.id)
      FROM public.employees t
      WHERE t.business_id = p_business_id
        AND (t.cloud_user_id = p_user_id OR t.auth_user_id = p_user_id)
        AND t.is_active = true
        AND t.deleted_at IS NULL
    ), '[]'::jsonb),
    'business_memberships', jsonb_build_array(jsonb_build_object(
      'id', v_membership.user_id,
      'business_id', v_membership.business_id,
      'user_id', v_membership.user_id,
      'role_id', v_membership.role_id,
      'status', v_membership.status,
      'joined_at', v_membership.joined_at,
      'created_at', v_membership.created_at,
      'updated_at', v_membership.updated_at
    )),
    'profiles', coalesce((
      SELECT jsonb_agg(to_jsonb(px) ORDER BY px.id)
      FROM public.profiles px
      WHERE px.id = p_user_id
    ), '[]'::jsonb),

    -- The employee restore path applies the authoritative claim's
    -- permissions after import, so these business-wide authorization
    -- tables must not be used to reconstruct other users' access.
    'roles', '[]'::jsonb,
    'role_permissions', '[]'::jsonb,
    'business_member_permissions', '[]'::jsonb,
    'permissions', '[]'::jsonb,
    'staff_invites', '[]'::jsonb,
    'devices', '[]'::jsonb,
    'audit_events', '[]'::jsonb
  )
  INTO v_snapshot
  FROM public.businesses b
  LEFT JOIN public.profiles p ON p.id = p_user_id
  WHERE b.id = p_business_id;

  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION USING errcode = 'P0002',
      message = 'Business not found';
  END IF;

  RETURN v_snapshot;
END;
$function$;

REVOKE ALL ON FUNCTION public.build_fulus_employee_restore_snapshot(uuid, uuid)
  FROM public, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.build_fulus_employee_restore_snapshot(uuid, uuid)
  TO service_role;
