-- Align the server staff-management boundary with the app's
-- employees.manage permission. Owners/admins retain full staff management;
-- managers with employees.manage may manage ordinary staff but cannot create
-- or alter owner/administrator access.

create or replace function public.create_staff_invite(
  target_business_id uuid,
  target_role_id uuid,
  target_email text,
  target_expires_hours integer default 24,
  target_actor_user_id uuid default null,
  target_permission_codes text[] default null,
  target_location_id uuid default null,
  target_employee_client_reference text default null,
  target_employee jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $
declare
  token text := replace(extensions.gen_random_uuid()::text || extensions.gen_random_uuid()::text, '-', '');
  invite public.staff_invites;
  employee_row public.employees;
  normalized_email text := nullif(lower(trim(target_email)), '');
  actor uuid := coalesce(target_actor_user_id, auth.uid());
  client_ref text := nullif(trim(target_employee_client_reference), '');
  employee_payload jsonb := coalesce(target_employee, '{}'::jsonb);
begin
  if actor is null or not exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = actor
      and bm.status = 'active'
      and (
        r.name in ('owner', 'admin')
        or public.staff_actor_has_permission(target_business_id, actor, 'employees.manage')
      )
  ) then
    raise exception using errcode='42501',
      message='Employee management access is required';
  end if;

  if normalized_email is null then
    raise exception using errcode='22023', message='An employee email is required';
  end if;
  if target_expires_hours < 1 or target_expires_hours > 168 then
    raise exception using errcode='22023', message='Invite expiry must be between 1 and 168 hours';
  end if;
  if not exists (
    select 1 from public.roles r
    where r.business_id = target_business_id
      and r.id = target_role_id
      and r.name <> 'owner'
  ) then
    raise exception using errcode='22023', message='Invalid staff role';
  end if;

  if public.staff_actor_has_permission(target_business_id, actor, 'employees.manage')
     and not exists (
       select 1
       from public.business_memberships bm
       join public.roles r on r.id = bm.role_id
       where bm.business_id = target_business_id
         and bm.user_id = actor
         and bm.status = 'active'
         and r.name in ('owner', 'admin')
     )
     and exists (
       select 1
       from public.roles r
       where r.id = target_role_id
         and r.business_id = target_business_id
         and r.name = 'admin'
     )
  then
    raise exception using errcode='42501',
      message='Managers cannot create administrator accounts';
  end if;
  if target_location_id is not null and not exists (
    select 1 from public.locations l
    where l.id = target_location_id
      and l.business_id = target_business_id
      and l.status = 'active'
  ) then
    raise exception using errcode='22023', message='Invite location is not active for this business';
  end if;
  if target_location_id is not null then
    perform set_config('request.jwt.claim.sub', actor::text, true);
    perform public.require_location_access(target_business_id, target_location_id);
  end if;

  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) as permission_item(permission_code)
    left join public.permissions p on p.code = permission_item.permission_code
    where p.id is null
  ) then
    raise exception using errcode='22023', message='Invite contains an unknown permission';
  end if;
  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) as permission_item(permission_code)
    where not public.staff_actor_has_permission(target_business_id, actor, permission_item.permission_code)
  ) then
    raise exception using errcode='42501', message='You cannot grant a permission you do not hold';
  end if;

  if client_ref is not null then
    select * into employee_row
    from public.employees
    where business_id = target_business_id
      and client_reference = client_ref
    for update;
  end if;

  if employee_row.id is null then
    insert into public.employees(
      business_id, client_reference, full_name, role, department, position,
      salary, phone, email, date_hired, location_id, is_active
    )
    values (
      target_business_id,
      coalesce(client_ref, 'invite:' || gen_random_uuid()::text),
      coalesce(nullif(trim(employee_payload->>'full_name'), ''), normalized_email),
      nullif(trim(employee_payload->>'role'), ''),
      nullif(trim(employee_payload->>'department'), ''),
      nullif(trim(employee_payload->>'position'), ''),
      nullif(employee_payload->>'salary', '')::numeric,
      nullif(trim(employee_payload->>'phone'), ''),
      normalized_email,
      nullif(employee_payload->>'date_hired', '')::date,
      target_location_id,
      true
    )
    returning * into employee_row;
  else
    update public.employees
    set full_name = coalesce(nullif(trim(employee_payload->>'full_name'), ''), full_name),
        role = coalesce(nullif(trim(employee_payload->>'role'), ''), role),
        department = nullif(trim(coalesce(employee_payload->>'department', department)), ''),
        position = nullif(trim(coalesce(employee_payload->>'position', position)), ''),
        salary = case when employee_payload ? 'salary' then nullif(employee_payload->>'salary', '')::numeric else salary end,
        phone = case when employee_payload ? 'phone' then nullif(trim(employee_payload->>'phone'), '') else phone end,
        email = normalized_email,
        date_hired = case when employee_payload ? 'date_hired' then nullif(employee_payload->>'date_hired', '')::date else date_hired end,
        location_id = target_location_id,
        is_active = true,
        deleted_at = null,
        updated_at = now()
    where id = employee_row.id
    returning * into employee_row;
  end if;

  insert into public.staff_invites(
    business_id, role_id, invited_email, token_hash, permission_codes,
    location_id, employee_id, expires_at, created_by
  )
  values (
    target_business_id, target_role_id, normalized_email,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    target_permission_codes, target_location_id, employee_row.id,
    now() + make_interval(hours => target_expires_hours), actor
  )
  returning * into invite;

  perform public._fulus_append_change(
    target_business_id, 'employee', employee_row.id, 'upsert', to_jsonb(employee_row)
  );

  insert into public.audit_events(
    business_id, actor_user_id, action, entity_type, entity_id, reason, metadata
  )
  values (
    target_business_id, actor, 'staff_invite_created', 'staff_invite', invite.id,
    'Staff invitation created',
    jsonb_build_object(
      'role_id', target_role_id,
      'employee_id', employee_row.id,
      'invited_email', invite.invited_email,
      'location_id', invite.location_id,
      'expires_at', invite.expires_at
    )
  );

  return jsonb_build_object(
    'invite_id', invite.id,
    'employee_id', employee_row.id,
    'token', token,
    'expires_at', invite.expires_at
  );
end;
$$;




create or replace function public.set_member_permission_overrides(
  target_business_id uuid,
  target_user_id uuid,
  target_permission_codes text[],
  target_actor_user_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := coalesce(target_actor_user_id, auth.uid());
  target_membership public.business_memberships;
begin
  if actor is null or not exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = actor
      and bm.status = 'active'
      and (
        r.name in ('owner', 'admin')
        or public.staff_actor_has_permission(target_business_id, actor, 'employees.manage')
      )
  ) then
    raise exception using errcode='42501',
      message='Employee management access is required';
  end if;

  if target_user_id is null or target_user_id = actor then
    raise exception using errcode='42501',
      message='An administrator cannot change their own staff permissions';
  end if;

  select bm.* into target_membership
  from public.business_memberships bm
  where bm.business_id = target_business_id
    and bm.user_id = target_user_id
    and bm.status = 'active'
  for update;

  if target_membership.id is null then
    raise exception using errcode='22023', message='Active staff membership not found';
  end if;

  if exists (
    select 1
    from public.roles r
    where r.id = target_membership.role_id
      and r.name = 'owner'
  ) then
    raise exception using errcode='42501',
      message='Owner permissions cannot be changed through staff access';
  end if;

  if exists (
    select 1
    from public.roles r
    join public.business_memberships actor_membership
      on actor_membership.role_id = r.id
    where actor_membership.business_id = target_business_id
      and actor_membership.user_id = actor
      and actor_membership.status = 'active'
      and r.name not in ('owner', 'admin')
      and exists (
        select 1
        from public.roles target_role
        where target_role.id = target_membership.role_id
          and target_role.business_id = target_business_id
          and target_role.name = 'admin'
      )
  ) then
    raise exception using errcode='42501',
      message='Managers cannot change administrator permissions';
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_permission_codes, array[]::text[])) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023', message='Unknown permission';
  end if;

  -- Match the local permission-editor invariant: an employee manager may only
  -- add or remove permissions they themselves hold. Existing permissions outside
  -- the actor's grant set may remain unchanged.
  if exists (
    with current_codes as (
      select p.code
      from public.permissions p
      where p.id in (
        select rp.permission_id
        from public.role_permissions rp
        where rp.role_id = target_membership.role_id
      )
      and not target_membership.permissions_overridden

      union

      select p.code
      from public.business_member_permissions mp
      join public.permissions p on p.id = mp.permission_id
      where mp.business_id = target_business_id
        and mp.user_id = target_user_id
        and target_membership.permissions_overridden
    ),
    requested_codes as (
      select distinct code
      from unnest(coalesce(target_permission_codes, array[]::text[])) code
    ),
    changed_codes as (
      select code from current_codes
      except
      select code from requested_codes
      union
      select code from requested_codes
      except
      select code from current_codes
    )
    select 1
    from changed_codes c
    where not public.staff_actor_has_permission(
      target_business_id,
      actor,
      c.code
    )
  ) then
    raise exception using errcode='42501',
      message='You cannot add or remove a permission you do not hold';
  end if;

  delete from public.business_member_permissions
  where business_id = target_business_id
    and user_id = target_user_id;

  insert into public.business_member_permissions(
    business_id, user_id, permission_id, granted_by, granted_at
  )
  select target_business_id, target_user_id, p.id, actor, now()
  from public.permissions p
  where p.code = any(coalesce(target_permission_codes, array[]::text[]));

  update public.business_memberships
  set permissions_overridden = true,
      updated_at = now()
  where id = target_membership.id;

  return true;
end;
$$;



create or replace function public.set_member_status(
  target_business_id uuid,
  target_membership_id uuid,
  target_status text,
  target_user_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $fn0$
declare
  target_member_user uuid;
begin
  if not exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = target_user_id
      and bm.status = 'active'
      and (
        r.name in ('owner', 'admin')
        or public.staff_actor_has_permission(target_business_id, target_user_id, 'employees.manage')
      )
  ) then
    raise exception using errcode='42501',
      message='Employee management access is required';
  end if;
  if target_status not in ('active', 'suspended', 'removed') then
    raise exception using errcode='22023', message='Invalid membership status';
  end if;

  if exists (
    select 1
    from public.business_memberships target_member
    join public.roles target_role on target_role.id = target_member.role_id
    where target_member.id = target_membership_id
      and target_member.business_id = target_business_id
      and (
        target_role.name = 'owner'
        or (
          target_role.name = 'admin'
          and not exists (
            select 1
            from public.business_memberships actor_member
            join public.roles actor_role on actor_role.id = actor_member.role_id
            where actor_member.business_id = target_business_id
              and actor_member.user_id = target_user_id
              and actor_member.status = 'active'
              and actor_role.name in ('owner', 'admin')
          )
        )
      )
  ) then
    raise exception using errcode='42501',
      message='Managers cannot change owner or administrator access';
  end if;

  select user_id into target_member_user
  from public.business_memberships
  where id = target_membership_id
    and business_id = target_business_id;

  if target_member_user = target_user_id then
    raise exception using errcode='42501',
      message='You cannot change your own employee access status';
  end if;

  if target_member_user is null then
    return false;
  end if;

  update public.business_memberships
  set status = target_status,
      updated_at = now()
  where id = target_membership_id
    and business_id = target_business_id;

  if target_status = 'active' then
    update public.devices
    set status = 'active', updated_at = now()
    where business_id = target_business_id
      and registered_by = target_member_user;
  else
    update public.devices
    set status = 'revoked', updated_at = now()
    where business_id = target_business_id
      and registered_by = target_member_user
      and status = 'active';
  end if;

  return true;
end;
$fn0$;
