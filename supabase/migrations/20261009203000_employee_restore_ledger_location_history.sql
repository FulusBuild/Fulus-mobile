-- Preserve customer-ledger entries tied to this location's historical sales
-- even when the legacy customer is unassigned/shared. The employee snapshot
-- already masks such customer rows as historical placeholders; ledger entries
-- without a sale/location reference remain excluded unless the customer itself
-- is safely owned by the assigned location.
do $employee_ledger_scope_patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.build_fulus_employee_restore_snapshot(uuid,uuid)'::regprocedure
  );
  v_patched := v_definition;

  v_old := E'        AND t.customer_id IN (\n' ||
    E'          SELECT c.id FROM public.customers c\n' ||
    E'          WHERE c.business_id = p_business_id\n' ||
    E'            AND c.location_id = v_location_id\n' ||
    E'        )\n' ||
    E'    ), ''[]''::jsonb),';
  v_new := E'        AND (\n' ||
    E'          t.customer_id IN (\n' ||
    E'            SELECT c.id FROM public.customers c\n' ||
    E'            WHERE c.business_id = p_business_id\n' ||
    E'              AND c.location_id = v_location_id\n' ||
    E'          )\n' ||
    E'          OR t.sale_id IN (\n' ||
    E'            SELECT s.id FROM public.sales s\n' ||
    E'            WHERE s.business_id = p_business_id\n' ||
    E'              AND s.location_id = v_location_id\n' ||
    E'          )\n' ||
    E'        )\n' ||
    E'    ), ''[]''::jsonb),';

  v_patched := replace(v_patched, v_old, v_new);
  if v_patched = v_definition
     or position('OR t.sale_id IN' in v_patched) = 0 then
    raise exception 'employee restore historical customer-ledger location patch did not apply';
  end if;

  execute v_patched;
end;
$employee_ledger_scope_patch$;
