-- Enforce per-location authorization at the authenticated API boundary.
-- Business owner/admin roles retain cross-location access; all other active
-- business members must have an active location_memberships row.

create or replace function public.require_location_access(
  target_business_id uuid,
  target_location_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_business_id is null or target_location_id is null then
    raise exception using errcode = '22023', message = 'Business and location are required';
  end if;

  if not exists (
    select 1
    from public.locations l
    where l.id = target_location_id
      and l.business_id = target_business_id
      and l.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'Location is not available in this business';
  end if;

  if public.is_business_admin(target_business_id)
     or public.is_location_member(target_location_id) then
    return;
  end if;

  raise exception using errcode = '42501', message = 'User is not authorized for this location';
end;
$$;

create or replace function public.require_sale_location_access(
  target_business_id uuid,
  target_sale_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_location_id uuid;
begin
  select s.location_id
    into v_location_id
  from public.sales s
  where s.id = target_sale_id
    and s.business_id = target_business_id;

  if v_location_id is null then
    raise exception using errcode = '42501', message = 'Sale is not available in this business';
  end if;

  perform public.require_location_access(target_business_id, v_location_id);
end;
$$;

create or replace function public.require_cash_shift_location_access(
  target_business_id uuid,
  target_shift_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_location_id uuid;
begin
  select c.location_id
    into v_location_id
  from public.cash_drawer_shifts c
  where c.id = target_shift_id
    and c.business_id = target_business_id;

  if v_location_id is null then
    raise exception using errcode = '42501', message = 'Cash drawer shift is not available in this business';
  end if;

  perform public.require_location_access(target_business_id, v_location_id);
end;
$$;

-- The API wrappers are the only authenticated execution surface for these
-- transactional functions. Patch their existing definitions at migration time
-- so authorization runs after the wrapper establishes the target user identity.
do $$
declare
  r record;
  v_def text;
  v_new text;
  v_expected text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in (
        'fulus_api_apply_inventory_adjustment',
        'fulus_api_cloud_open_cash_drawer_shift',
        'fulus_api_cloud_record_income',
        'fulus_api_create_sale_atomic',
        'fulus_api_record_expense',
        'fulus_api_set_inventory_quantity',
        'fulus_api_update_expense'
      )
      and pg_get_function_identity_arguments(p.oid) like 'target_user_id uuid, target_business_id uuid,%target_location_id uuid%'
  loop
    v_def := pg_get_functiondef(r.oid);

    if v_def like '%require_location_access(target_business_id, target_location_id)%' then
      continue;
    end if;

    v_expected := 'begin';
    if position(v_expected in lower(v_def)) = 0 then
      raise exception 'Could not locate function body for %.%', r.proname, r.args;
    end if;

    v_new := regexp_replace(
      v_def,
      'begin',
      'begin
  perform set_config(''request.jwt.claim.sub'', target_user_id::text, true);
  perform public.require_location_access(target_business_id, target_location_id);',
      1,
      1,
      'i'
    );

    execute v_new;
  end loop;
end;
$$;

do $$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'fulus_api_create_return_atomic'
  loop
    v_def := pg_get_functiondef(r.oid);

    if v_def like '%require_sale_location_access(target_business_id, target_sale_id)%' then
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      'begin',
      'begin
  perform set_config(''request.jwt.claim.sub'', target_user_id::text, true);
  perform public.require_sale_location_access(target_business_id, target_sale_id);',
      1,
      1,
      'i'
    );

    execute v_new;
  end loop;
end;
$$;

do $$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'fulus_api_record_sale_payment'
  loop
    v_def := pg_get_functiondef(r.oid);

    if v_def like '%require_sale_location_access(target_business_id, target_sale_id)%' then
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      'begin',
      'begin
  perform set_config(''request.jwt.claim.sub'', target_user_id::text, true);
  perform public.require_sale_location_access(target_business_id, target_sale_id);',
      1,
      1,
      'i'
    );

    execute v_new;
  end loop;
end;
$$;

do $$
declare
  r record;
  v_def text;
  v_new text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'fulus_api_cloud_close_cash_drawer_shift'
  loop
    v_def := pg_get_functiondef(r.oid);

    if v_def like '%require_cash_shift_location_access(target_business_id, target_shift_id)%' then
      continue;
    end if;

    v_new := regexp_replace(
      v_def,
      'begin',
      'begin
  perform set_config(''request.jwt.claim.sub'', target_user_id::text, true);
  perform public.require_cash_shift_location_access(target_business_id, target_shift_id);',
      1,
      1,
      'i'
    );

    execute v_new;
  end loop;
end;
$$;

revoke execute on function public.require_location_access(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.require_sale_location_access(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.require_cash_shift_location_access(uuid, uuid) from public, anon, authenticated;
