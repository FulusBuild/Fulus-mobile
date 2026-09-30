-- Invitations carry the employee location, so creating an invite is also a
-- location-scoped employee-management operation.
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
as $$
declare
  token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
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
      and r.name in ('owner', 'admin')
  ) then
    raise exception using errcode='42501',
      message='Only an owner or admin may create staff invites';
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
    from unnest(target_permission_codes) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023', message='Invite contains an unknown permission';
  end if;
  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) code
    where not public.staff_actor_has_permission(target_business_id, actor, code)
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
    encode(digest(token, 'sha256'), 'hex'),
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


revoke all on function public.create_staff_invite(
  uuid,uuid,text,integer,uuid,text[],uuid,text,jsonb
) from public,anon,authenticated,service_role;
grant execute on function public.create_staff_invite(
  uuid,uuid,text,integer,uuid,text[],uuid,text,jsonb
) to service_role;
