-- Every unassigned employee must have an owner/admin review item. This
-- trigger also covers legacy clients that still upload a roster row without a
-- location; such a row stays unassigned and receives no active location access.
create or replace function public._fulus_queue_unassigned_employee_location_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.location_id is null then
    insert into public.location_ownership_review(
      business_id, entity_type, entity_id, candidate_location_ids,
      classification, reason
    )
    values (
      new.business_id, 'employee', new.id, '{}'::uuid[],
      'unassigned',
      'No explicit location ownership exists for this legacy employee'
    )
    on conflict (entity_type, entity_id) do update
      set business_id = excluded.business_id,
          candidate_location_ids = '{}'::uuid[],
          classification = 'unassigned',
          reason = excluded.reason,
          created_at = pg_catalog.now(),
          reviewed_at = null,
          reviewed_by = null;
  end if;
  return new;
end;
$function$;

revoke all on function public._fulus_queue_unassigned_employee_location_review()
  from public, anon, authenticated;

drop trigger if exists employees_unassigned_location_review on public.employees;
create trigger employees_unassigned_location_review
after insert or update of location_id on public.employees
for each row execute function public._fulus_queue_unassigned_employee_location_review();

-- Backfill again after installing the trigger so any rows created between
-- earlier migrations and this one are also made reviewable.
insert into public.location_ownership_review(
  business_id, entity_type, entity_id, candidate_location_ids,
  classification, reason
)
select e.business_id, 'employee', e.id, '{}'::uuid[],
       'unassigned',
       'No explicit location ownership exists for this legacy employee'
from public.employees e
where e.location_id is null
on conflict (entity_type, entity_id) do update
  set business_id = excluded.business_id,
      candidate_location_ids = '{}'::uuid[],
      classification = 'unassigned',
      reason = excluded.reason,
      created_at = pg_catalog.now(),
      reviewed_at = null,
      reviewed_by = null;

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

    if employee_row.id is not null
       and target_location_id is not null
       and employee_row.location_id is distinct from target_location_id then
      raise exception using errcode='42501',
        message='Employee location ownership can only be assigned through the ownership review flow';
    end if;

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
    if employee_row.location_id is null then
      raise exception using errcode='42501',
        message='Employee location ownership is unresolved; resolve the ownership review before editing';
    end if;
    if target_location_id is not null
       and target_location_id is distinct from employee_row.location_id then
      raise exception using errcode='42501',
        message='Employee location ownership cannot be changed by roster update';
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
        location_id = employee_row.location_id,
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

    -- The employee roster has one effective location. Keep the cloud
    -- location membership in lockstep with that authoritative roster field.
    delete from public.location_memberships
    where business_id = target_business_id
      and user_id = membership_user
      and status = 'active';

    if employee_row.location_id is not null and employee_row.is_active then
      insert into public.location_memberships(
        business_id, user_id, location_id, status, created_at, updated_at
      )
      values (
        target_business_id, membership_user, employee_row.location_id,
        'active', now(), now()
      )
      on conflict (location_id, user_id)
      do update set
        business_id = excluded.business_id,
        status = 'active',
        updated_at = now();
    end if;

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
