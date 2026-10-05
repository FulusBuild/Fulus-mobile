-- Close the employee restore branch of the strict money wire contract.
-- The shared restore wrapper routes non-admin users through this function.

do $migration$
declare
  v_definition text;
begin
  select pg_catalog.pg_get_functiondef(
    'public.build_fulus_employee_restore_snapshot(uuid,uuid)'::regprocedure
  ) into v_definition;

  v_definition := pg_catalog.regexp_replace(
    v_definition,
    'RETURN[[:space:]]+v_snapshot;',
    'RETURN public._fulus_money_wire_jsonb(v_snapshot);',
    1,
    1,
    'i'
  );

  if position('public._fulus_money_wire_jsonb(v_snapshot)' in v_definition) = 0 then
    raise exception 'Employee restore snapshot function was not updated to the strict money wire contract';
  end if;

  execute v_definition;
end;
$migration$;
