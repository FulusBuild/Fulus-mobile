-- Keep the employee invitation claim boundary pinned to an empty
-- SECURITY DEFINER search path. The claim token is a bearer credential, so
-- function-name resolution must never depend on caller-controlled schemas.

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
  where token_hash = encode(extensions.digest(target_token, 'sha256'), 'hex')
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

  -- An employee has one effective location. Remove stale active
  -- memberships before assigning the invitation's location so a re-claim or
  -- repaired invitation cannot silently expand the employee's access scope.
  delete from public.location_memberships
  where business_id = invite.business_id
    and user_id = target_user_id
    and status = 'active';

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
    'employee', to_jsonb(employee_row),
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

