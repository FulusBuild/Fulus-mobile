-- Employee roster becomes a first-class cloud-synchronized business entity.
-- Auth membership/role/permissions remain authoritative for access; this table
-- owns the HR roster fields and links to the membership when one exists.

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_reference text not null,
  membership_id uuid null references public.business_memberships(id) on delete set null,
  auth_user_id uuid null references auth.users(id) on delete set null,
  full_name text not null,
  role text null,
  department text null,
  position text null,
  salary numeric null,
  phone text null,
  email text null,
  date_hired date null,
  location_id uuid null references public.locations(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz null,
  unique (business_id, client_reference)
);

create index if not exists employees_business_updated_idx
  on public.employees (business_id, updated_at desc);
create index if not exists employees_business_auth_idx
  on public.employees (business_id, auth_user_id);
create index if not exists employees_business_location_idx
  on public.employees (business_id, location_id);

alter table public.employees enable row level security;
revoke all on table public.employees from anon, authenticated;
grant select on table public.employees to authenticated;

drop policy if exists employees_read_access on public.employees;
create policy employees_read_access
  on public.employees
  for select
  to authenticated
  using (
    public.has_permission(business_id, 'employees.read')
    or public.has_permission(business_id, 'employees.manage')
    or auth.uid() = auth_user_id
  );

alter table public.staff_invites
  add column if not exists employee_id uuid references public.employees(id) on delete set null;

create index if not exists staff_invites_employee_idx
  on public.staff_invites (employee_id);

-- Replace the latest 7-argument invite contract with an employee-aware contract.
drop function if exists public.create_staff_invite(uuid,uuid,text,integer,uuid,text[],uuid);

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

revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[],uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[],uuid,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[],uuid,text,jsonb)
  to service_role;

-- Employee mutations use the same durable idempotency/OCC contract as the
-- existing sync entities. The service boundary supplies the verified actor
-- and registered device; database authorization remains authoritative.
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
  if target_location_id is not null and not exists (
    select 1 from public.locations
    where id=target_location_id and business_id=target_business_id and status='active'
  ) then
    raise exception using errcode='22023', message='Employee location is not active for this business';
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
) from public,anon,authenticated;
grant execute on function public.fulus_api_mutate_employee(
  uuid,uuid,uuid,text,text,uuid,text,text,text,text,text,numeric,text,text,date,uuid,boolean,bigint,text
) to service_role;

-- Claiming an invite links the same roster record to the authoritative cloud
-- membership/auth identity. This is the bridge between HR data and access.
drop function if exists public.claim_staff_invite(text,uuid);

create or replace function public.claim_staff_invite(
  target_token text,
  target_user_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $claim$
declare
  invite public.staff_invites;
  membership public.business_memberships;
  role_row public.roles;
  account_email text;
  profile_name text;
  selected_location_id uuid;
  employee_row public.employees;
  now_ts timestamptz := now();
begin
  if target_user_id is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;

  select email into account_email from auth.users where id = target_user_id;
  if account_email is null then
    raise exception using errcode='42501', message='Authenticated account not found';
  end if;

  select * into invite
  from public.staff_invites
  where token_hash = encode(digest(target_token, 'sha256'), 'hex')
  for update;
  if invite.id is null then raise exception using errcode='22023', message='Invalid invite'; end if;
  if invite.claimed_at is not null then raise exception using errcode='23505', message='Invite already claimed'; end if;
  if invite.expires_at <= now_ts then raise exception using errcode='22023', message='Invite expired'; end if;
  if invite.invited_email is not null and lower(account_email) <> lower(invite.invited_email) then
    raise exception using errcode='42501', message='Invite email does not match the signed-in account';
  end if;

  select * into role_row
  from public.roles where id = invite.role_id and business_id = invite.business_id;
  if role_row.id is null or role_row.name = 'owner' then
    raise exception using errcode='22023', message='Invite role is no longer valid';
  end if;

  if invite.location_id is not null and not exists (
    select 1 from public.locations
    where id = invite.location_id and business_id = invite.business_id and status = 'active'
  ) then
    raise exception using errcode='22023', message='Invite location is no longer active';
  end if;

  select * into membership
  from public.business_memberships
  where business_id = invite.business_id and user_id = target_user_id
  for update;

  if membership.id is null then
    insert into public.business_memberships(
      business_id, user_id, role_id, status, joined_at, permissions_overridden
    )
    values (
      invite.business_id, target_user_id, invite.role_id, 'active',
      now_ts, invite.permission_codes is not null
    )
    returning * into membership;
  else
    update public.business_memberships
    set role_id = invite.role_id, status = 'active',
        joined_at = coalesce(joined_at, now_ts),
        permissions_overridden = invite.permission_codes is not null,
        updated_at = now_ts
    where id = membership.id
    returning * into membership;
  end if;

  delete from public.business_member_permissions
  where business_id = invite.business_id and user_id = target_user_id;
  if invite.permission_codes is not null then
    insert into public.business_member_permissions(
      business_id, user_id, permission_id, granted_by, granted_at
    )
    select invite.business_id, target_user_id, p.id, invite.created_by, now_ts
    from public.permissions p where p.code = any(invite.permission_codes);
  end if;

  selected_location_id := invite.location_id;
  if selected_location_id is null then
    select lm.location_id into selected_location_id
    from public.location_memberships lm
    where lm.business_id = invite.business_id and lm.user_id = target_user_id and lm.status = 'active'
    order by lm.created_at limit 1;
  end if;
  if selected_location_id is null then
    select l.id into selected_location_id
    from public.locations l
    where l.business_id = invite.business_id and l.status = 'active'
    order by l.created_at limit 1;
  end if;
  if selected_location_id is not null then
    insert into public.location_memberships(business_id, location_id, user_id, status)
    values (invite.business_id, selected_location_id, target_user_id, 'active')
    on conflict (location_id, user_id) do update set status='active', updated_at=now_ts;
  end if;

  select p.full_name into profile_name from public.profiles p where p.id = target_user_id;

  if invite.employee_id is not null then
    select * into employee_row
    from public.employees
    where id = invite.employee_id and business_id = invite.business_id
    for update;
    if employee_row.id is not null then
      update public.employees
      set membership_id = membership.id,
          auth_user_id = target_user_id,
          full_name = coalesce(nullif(trim(profile_name), ''), full_name),
          email = account_email,
          location_id = coalesce(invite.location_id, location_id),
          is_active = true,
          deleted_at = null,
          updated_at = now_ts
      where id = employee_row.id
      returning * into employee_row;
      perform public._fulus_append_change(
        invite.business_id, 'employee', employee_row.id, 'upsert', to_jsonb(employee_row)
      );
    end if;
  end if;

  update public.staff_invites
  set claimed_at = now_ts, claimed_by = target_user_id, updated_at = now_ts
  where id = invite.id;

  insert into public.audit_events(
    business_id, actor_user_id, action, entity_type, entity_id, metadata
  )
  values (
    invite.business_id, target_user_id, 'staff_invite_claimed',
    'business_membership', membership.id,
    jsonb_build_object('invite_id', invite.id, 'role_id', invite.role_id, 'location_id', selected_location_id, 'employee_id', invite.employee_id)
  );

  return jsonb_build_object(
    'business_id', membership.business_id,
    'membership_id', membership.id,
    'user_id', target_user_id,
    'role_id', membership.role_id,
    'role_name', role_row.name,
    'full_name', coalesce(nullif(trim(profile_name), ''), coalesce(employee_row.full_name, '')),
    'email', account_email,
    'location_id', selected_location_id,
    'employee_id', employee_row.id,
    'permission_codes',
      coalesce(
        invite.permission_codes,
        array(
          select p.code from public.role_permissions rp
          join public.permissions p on p.id = rp.permission_id
          where rp.role_id = invite.role_id
        )
      )
  );
end;
$claim$;

revoke all on function public.claim_staff_invite(text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.claim_staff_invite(text,uuid) to service_role;
