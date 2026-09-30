-- Apply employee-specific location authorization after the employee
-- roster base exists. Owners/admins retain cross-location access; other staff
-- must belong to the effective employee location.

create or replace function public.fulus_api_mutate_employee(
  target_business_id uuid,
  target_user_id uuid,
  target_device_id uuid,
  target_operation_id text,
  target_operation text,
  target_employee_id uuid default null,
  target_client_reference text default null,
  target_full_name text default null,
  target_role text default null,
  target_department text default null,
  target_position text default null,
  target_salary numeric default null,
  target_phone text default null,
  target_email text default null,
  target_date_hired date default null,
  target_location_id uuid default null,
  target_is_active boolean default true,
  target_base_cursor bigint default null,
  target_request_hash text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  idem public.idempotency_keys%rowtype;
  employee_row public.employees;
  result jsonb;
  change_sequence bigint;
  membership_user uuid;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if target_operation not in ('create','update') then
    raise exception using errcode='22023', message='Unsupported employee operation';
  end if;
  if not public.user_has_permission(target_business_id, target_user_id, 'employees.manage') then
    raise exception using errcode='42501', message='Employee management permission required';
  end if;
  if not exists (
    select 1 from public.devices
    where id=target_device_id
      and business_id=target_business_id
      and registered_by=target_user_id
      and status='active'
  ) then
    raise exception using errcode='42501', message='Device is not registered or active';
  end if;
  if target_operation = 'create' and target_location_id is not null then
    perform public.require_location_access(target_business_id, target_location_id);
  end if;

  insert into public.idempotency_keys(
    business_id, device_id, user_id, key, operation_type, request_hash
  )
  values (
    target_business_id, target_device_id, target_user_id, target_operation_id,
    'employee.' || target_operation, target_request_hash
  )
  on conflict (business_id, key) do nothing;

  select * into idem
  from public.idempotency_keys
  where business_id = target_business_id and key = target_operation_id
  for update;

  if idem.device_id is distinct from target_device_id
     or idem.user_id is distinct from target_user_id
     or idem.operation_type <> 'employee.' || target_operation
     or idem.request_hash <> target_request_hash then
    raise exception using errcode='P0009',
      message='Operation id was already used with a different request';
  end if;
  if idem.completed_at is not null and idem.response_body is not null then
    return idem.response_body;
  end if;

  if target_operation = 'create' then
    if nullif(trim(target_client_reference), '') is null then
      raise exception using errcode='22023', message='Employee client_reference is required';
    end if;
    select * into employee_row
    from public.employees
    where business_id = target_business_id
      and client_reference = trim(target_client_reference)
    for update;

    if employee_row.id is null then
      insert into public.employees(
        business_id, client_reference, full_name, role, department, position,
        salary, phone, email, date_hired, location_id, is_active
      )
      values (
        target_business_id, trim(target_client_reference), trim(coalesce(target_full_name,'')),
        nullif(trim(target_role), ''), nullif(trim(target_department), ''),
        nullif(trim(target_position), ''), target_salary, nullif(trim(target_phone), ''),
        nullif(lower(trim(target_email)), ''), target_date_hired, target_location_id,
        target_is_active
      )
      returning * into employee_row;
    else
      update public.employees
      set full_name = trim(coalesce(target_full_name, full_name)),
          role = nullif(trim(coalesce(target_role, role)), ''),
          department = nullif(trim(coalesce(target_department, department)), ''),
          position = nullif(trim(coalesce(target_position, position)), ''),
          salary = target_salary,
          phone = nullif(trim(coalesce(target_phone, phone)), ''),
          email = nullif(lower(trim(coalesce(target_email, email))), ''),
          date_hired = coalesce(target_date_hired, date_hired),
          location_id = coalesce(target_location_id, location_id),
          is_active = target_is_active,
          deleted_at = case when target_is_active then null else coalesce(deleted_at, now()) end,
          updated_at = now()
      where id = employee_row.id
      returning * into employee_row;
    end if;
  else
    if target_employee_id is null then
      raise exception using errcode='22023', message='Employee update requires server_id';
    end if;
    if target_base_cursor is not null and exists (
      select 1 from public.sync_changes sc
      where sc.business_id = target_business_id
        and sc.entity_type = 'employee'
        and sc.entity_id = target_employee_id
        and sc.sequence > target_base_cursor
    ) then
      raise exception using errcode='P0008',
        message='SYNC_CONFLICT: Employee changed on another device after this edit was created';
    end if;

    select * into employee_row
    from public.employees
    where id = target_employee_id and business_id = target_business_id
    for update;
    if employee_row.id is null then
      raise exception using errcode='P0002', message='Employee not found';
    end if;

    if target_location_id is not null then
      perform public.require_location_access(target_business_id, target_location_id);
    elsif employee_row.location_id is not null then
      perform public.require_location_access(target_business_id, employee_row.location_id);
    end if;

    update public.employees
    set full_name = coalesce(trim(target_full_name), full_name),
        role = case when target_role is null then role else nullif(trim(target_role), '') end,
        department = case when target_department is null then department else nullif(trim(target_department), '') end,
        position = case when target_position is null then position else nullif(trim(target_position), '') end,
        salary = target_salary,
        phone = case when target_phone is null then phone else nullif(trim(target_phone), '') end,
        email = case when target_email is null then email else nullif(lower(trim(target_email)), '') end,
        date_hired = target_date_hired,
        location_id = target_location_id,
        is_active = target_is_active,
        deleted_at = case when target_is_active then null else coalesce(deleted_at, now()) end,
        updated_at = now()
    where id = target_employee_id
    returning * into employee_row;
  end if;

  if employee_row.auth_user_id is not null then
    membership_user := employee_row.auth_user_id;
    update public.business_memberships
    set status = case when employee_row.is_active then 'active' else 'suspended' end,
        updated_at = now()
    where business_id = target_business_id
      and user_id = membership_user;
    if not employee_row.is_active then
      update public.devices
      set status = 'revoked', updated_at = now()
      where business_id = target_business_id
        and registered_by = membership_user
        and status = 'active';
    end if;
  end if;

  perform public._fulus_append_change(
    target_business_id, 'employee', employee_row.id, 'upsert', to_jsonb(employee_row)
  );

  select max(sc.sequence) into change_sequence
  from public.sync_changes sc
  where sc.business_id = target_business_id
    and sc.entity_type = 'employee'
    and sc.entity_id = employee_row.id;

  result := jsonb_build_object(
    'data', jsonb_build_object(
      'entity_id', employee_row.id,
      'employee', to_jsonb(employee_row),
      'sync_sequence', change_sequence,
      'status', case when target_operation = 'create' then 'created' else 'updated' end,
      'server_authoritative', true
    )
  );

  update public.idempotency_keys
  set response_status=200, response_body=result, completed_at=now()
  where id=idem.id;

  return result;
end;
$$;


revoke all on function public.fulus_api_mutate_employee(
  uuid,uuid,uuid,text,text,uuid,text,text,text,text,text,numeric,text,text,date,uuid,boolean,bigint,text
) from public,anon,authenticated,service_role;
grant execute on function public.fulus_api_mutate_employee(
  uuid,uuid,uuid,text,text,uuid,text,text,text,text,text,numeric,text,text,date,uuid,boolean,bigint,text
) to service_role;

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
