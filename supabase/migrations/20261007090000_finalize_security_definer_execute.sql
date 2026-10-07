-- Final database security invariant: SECURITY DEFINER functions in the
-- public schema are service-side implementation boundaries. They must not be
-- directly callable by browser/client roles.
--
-- Revoke both explicit and PUBLIC-derived EXECUTE, then restore the intended
-- service_role boundary. Existing function-specific grants to other trusted
-- server roles are intentionally left untouched because this migration only
-- changes the two Supabase client roles.
do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      fn.signature
    );
    execute format(
      'grant execute on function %s to service_role',
      fn.signature
    );
  end loop;
end
$$;
