-- Catalog-level security invariants. This suite intentionally tests the
-- final database state, not the text of individual migrations.
--
-- Supabase recommends pinned search_path for SECURITY DEFINER functions,
-- explicit EXECUTE grants, and RLS on every exposed table.

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and not exists (
      select 1
      from unnest(coalesce(p.proconfig, array[]::text[])) cfg
      where cfg like 'search_path=%'
    );

  if v_count > 0 then
    raise exception 'FAIL: % SECURITY DEFINER public functions do not pin search_path', v_count;
  end if;

  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and exists (
      select 1
      from unnest(coalesce(p.proconfig, array[]::text[])) cfg
      where cfg like 'search_path=%'
        and cfg like '%$user%'
    );

  if v_count > 0 then
    raise exception 'FAIL: % SECURITY DEFINER public functions allow $user in search_path', v_count;
  end if;

  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.prosecdef
    and (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );

  if v_count > 0 then
    raise exception 'FAIL: % SECURITY DEFINER public functions are directly executable by anon/authenticated', v_count;
  end if;

  select count(*) into v_count
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relkind in ('r','p')
    and not c.relrowsecurity;

  if v_count > 0 then
    raise exception 'FAIL: % exposed public tables do not have RLS enabled', v_count;
  end if;
end
$$;

do $$
declare
  sale_def text;
  return_def text;
begin
  select pg_get_functiondef(
    'public.fulus_api_create_sale_atomic_v2(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb)'::regprocedure
  ) into sale_def;

  if position('require_location_access' in sale_def) = 0 then
    raise exception 'FAIL: V2 sale entrypoint does not enforce location authorization';
  end if;

  select pg_get_functiondef(
    'public.fulus_api_create_return_atomic_v2(uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb)'::regprocedure
  ) into return_def;

  if position('require_sale_location_access' in return_def) = 0 then
    raise exception 'FAIL: V2 return entrypoint does not enforce sale-location authorization';
  end if;
end
$$;

do $security$
declare
  v_count integer;
  v_check text;
begin
  select count(*) into v_count
  from pg_policies
  where schemaname='storage'
    and tablename='objects'
    and policyname in (
      'product images update for business members',
      'product images delete for business members'
    );

  if v_count > 0 then
    raise exception 'FAIL: product image storage still exposes update/delete policies';
  end if;

  select count(*) into v_count
  from pg_policies
  where schemaname='storage'
    and tablename='objects'
    and policyname='product images upload for catalog managers'
    and cmd='INSERT'
    and with_check like '%catalog.manage%';

  if v_count <> 1 then
    raise exception 'FAIL: product image insert policy is not bound to catalog.manage';
  end if;
end
$security$;

select 'PASS: SECURITY DEFINER, function grants, RLS, and V2 location-authorization invariants hold' as result;
