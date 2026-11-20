-- Archiving a customer hides them from active customer workflows but retains
-- their credit account. Existing debt must remain collectible after archive.
-- Preserve the full repayment function and its permission/idempotency rules;
-- remove only the active-customer predicate from its locked account lookup.
do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.record_customer_repayment(uuid,uuid,numeric,text,text,text,uuid)'::regprocedure
  ) into v_definition;

  if position('and is_active = true' in v_definition) = 0 then
    raise exception 'Expected active-customer guard was not found in repayment function';
  end if;

  v_updated := replace(v_definition, 'and is_active = true', '');
  execute v_updated;
end;
$$;
