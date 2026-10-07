-- Final database security invariant: every exposed public table must have
-- Row Level Security enabled. Existing policies remain the source of truth for
-- client access; tables without client policies remain inaccessible to
-- anon/authenticated while privileged server roles continue to operate.
do $$
declare
  tbl record;
begin
  for tbl in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','p')
      and not c.relrowsecurity
  loop
    execute format(
      'alter table public.%I enable row level security',
      tbl.table_name
    );
  end loop;
end
$$;
