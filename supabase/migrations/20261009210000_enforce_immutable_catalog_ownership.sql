-- Enforce tenant immutability even for privileged direct table updates.
-- Normal API paths already prevent ownership moves; the trigger must remain
-- the invariant if an administrator or service integration bypasses them.
do $ownership_immutability_patch$
declare
  v_definition text;
  v_patched text;
  v_old text;
  v_new text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.guard_location_owned_record()'::regprocedure
  );
  v_patched := v_definition;

  v_old := E'  if tg_op = ''UPDATE'' and old.location_id is not null\n' ||
    E'     and new.location_id is distinct from old.location_id then';
  v_new := E'  if tg_op = ''UPDATE'' and (\n' ||
    E'     new.business_id is distinct from old.business_id\n' ||
    E'     or (old.location_id is not null and new.location_id is distinct from old.location_id)\n' ||
    E'  ) then';
  v_patched := replace(v_patched, v_old, v_new);

  v_old := E'     and (tg_op = ''INSERT'' or new.location_id is distinct from old.location_id)\n';
  v_new := E'     and (tg_op = ''INSERT''\n' ||
    E'          or new.location_id is distinct from old.location_id\n' ||
    E'          or new.business_id is distinct from old.business_id)\n';
  v_patched := replace(v_patched, v_old, v_new);

  if v_patched = v_definition
     or position('new.business_id is distinct from old.business_id' in v_patched) = 0
     or position('Location ownership cannot be changed after assignment' in v_patched) = 0 then
    raise exception 'catalog business/location immutability patch did not apply';
  end if;

  execute v_patched;
end;
$ownership_immutability_patch$;
