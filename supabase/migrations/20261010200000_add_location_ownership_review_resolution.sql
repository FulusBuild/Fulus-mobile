-- Explicit, administrator-only resolution for legacy catalog ownership.
-- Resolution assigns only the previously-unassigned record and never rewrites
-- historical sales, inventory, returns, or customer-ledger references.

create or replace function public.fulus_api_resolve_location_ownership(
  target_user_id uuid,
  target_business_id uuid,
  target_review_id uuid,
  target_location_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_role_name text;
  v_review public.location_ownership_review%rowtype;
  v_location_business_id uuid;
  v_entity_location_id uuid;
  v_employee public.employees%rowtype;
begin
  if target_user_id is null or target_business_id is null
     or target_review_id is null or target_location_id is null then
    raise exception using errcode = '22004', message = 'All ownership resolution arguments are required';
  end if;

  select r.name into v_role_name
  from public.business_memberships bm
  join public.roles r on r.id = bm.role_id and r.business_id = bm.business_id
  where bm.user_id = target_user_id
    and bm.business_id = target_business_id
    and bm.status = 'active';

  if v_role_name is distinct from 'owner'
     and v_role_name is distinct from 'admin' then
    raise exception using errcode = '42501', message = 'Business administrator access required';
  end if;

  select * into v_review
  from public.location_ownership_review
  where id = target_review_id
    and business_id = target_business_id
    and reviewed_at is null
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Pending ownership review not found';
  end if;

  select l.business_id into v_location_business_id
  from public.locations l
  where l.id = target_location_id and l.status = 'active'
  for share;

  if v_location_business_id is distinct from target_business_id then
    raise exception using errcode = '23503', message = 'Selected location must be active and belong to the same business';
  end if;

  if v_review.entity_type = 'product' then
    select p.location_id into v_entity_location_id
    from public.products p
    where p.id = v_review.entity_id and p.business_id = target_business_id
    for update;

    if not found or v_entity_location_id is not null then
      raise exception using errcode = 'P0002', message = 'Product is missing or already has an owner location';
    end if;

    update public.products
    set location_id = target_location_id
    where id = v_review.entity_id and business_id = target_business_id
      and location_id is null;
  elsif v_review.entity_type = 'customer' then
    select c.location_id into v_entity_location_id
    from public.customers c
    where c.id = v_review.entity_id and c.business_id = target_business_id
    for update;

    if not found or v_entity_location_id is not null then
      raise exception using errcode = 'P0002', message = 'Customer is missing or already has an owner location';
    end if;

    update public.customers
    set location_id = target_location_id
    where id = v_review.entity_id and business_id = target_business_id
      and location_id is null;

    -- Customer ownership is location-scoped, so publish the canonical row
    -- after assignment. Without this change-feed event, devices that already
    -- synced the unassigned legacy customer keep it hidden and unsellable.
    perform public._fulus_append_change(
      target_business_id,
      'customer',
      v_review.entity_id,
      'upsert',
      (
        select pg_catalog.to_jsonb(c)
        from public.customers c
        where c.id = v_review.entity_id
          and c.business_id = target_business_id
      )
    );
  elsif v_review.entity_type = 'employee' then
    select e.* into v_employee
    from public.employees e
    where e.id = v_review.entity_id and e.business_id = target_business_id
    for update;

    if not found or v_employee.location_id is not null then
      raise exception using errcode = 'P0002', message = 'Employee is missing or already has an owner location';
    end if;

    update public.employees e
    set location_id = target_location_id, updated_at = pg_catalog.now()
    where e.id = v_review.entity_id
      and e.business_id = target_business_id
      and e.location_id is null
    returning e.* into v_employee;

    if not found then
      raise exception using errcode = '40001', message = 'Employee ownership was concurrently resolved';
    end if;

    -- The employee's roster location and active location membership are one
    -- ownership boundary. Do not activate an inactive employee during review.
    if v_employee.auth_user_id is not null then
      delete from public.location_memberships
      where business_id = target_business_id
        and user_id = v_employee.auth_user_id
        and status = 'active';

      if v_employee.is_active then
        insert into public.location_memberships(
          business_id, user_id, location_id, status, created_at, updated_at
        )
        values (
          target_business_id, v_employee.auth_user_id, target_location_id,
          'active', pg_catalog.now(), pg_catalog.now()
        )
        on conflict (location_id, user_id)
        do update set
          business_id = excluded.business_id,
          status = 'active',
          updated_at = pg_catalog.now();
      end if;
    end if;

    perform public._fulus_append_change(
      target_business_id, 'employee', v_employee.id, 'upsert', pg_catalog.to_jsonb(v_employee)
    );
  else
    raise exception using errcode = '22023', message = 'Unsupported ownership review entity type';
  end if;

  update public.location_ownership_review
  set reviewed_at = pg_catalog.now(), reviewed_by = target_user_id
  where id = v_review.id and reviewed_at is null;

  if not found then
    raise exception using errcode = '40001', message = 'Ownership review was concurrently resolved';
  end if;

  return pg_catalog.jsonb_build_object(
    'review_id', v_review.id,
    'entity_type', v_review.entity_type,
    'entity_id', v_review.entity_id,
    'business_id', target_business_id,
    'location_id', target_location_id,
    'reviewed_at', pg_catalog.now(),
    'reviewed_by', target_user_id
  );
end;
$function$;

revoke all on function public.fulus_api_resolve_location_ownership(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.fulus_api_resolve_location_ownership(uuid, uuid, uuid, uuid)
  to service_role;
