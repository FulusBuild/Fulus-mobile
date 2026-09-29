-- Preserve the employee's assigned operating location when moving their
-- login to another device. A cross-device invite must not silently fall back
-- to the business's first location.

alter table public.staff_invites
  add column if not exists location_id uuid references public.locations(id) on delete set null;

create or replace function public.create_staff_invite(
  target_business_id uuid,
  target_role_id uuid,
  target_email text,
  target_expires_hours integer default 24,
  target_actor_user_id uuid default null,
  target_permission_codes text[] default null,
  target_location_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  invite public.staff_invites;
  normalized_email text := nullif(lower(trim(target_email)), '');
  actor uuid := coalesce(target_actor_user_id, auth.uid());
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
    raise exception using errcode='22023',
      message='Invite expiry must be between 1 and 168 hours';
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
    select 1
    from public.locations l
    where l.id = target_location_id
      and l.business_id = target_business_id
      and l.status = 'active'
  ) then
    raise exception using errcode='22023',
      message='Invite location is not active for this business';
  end if;

  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023',
      message='Invite contains an unknown permission';
  end if;

  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) code
    where not public.staff_actor_has_permission(
      target_business_id,
      actor,
      code
    )
  ) then
    raise exception using errcode='42501',
      message='You cannot grant a permission you do not hold';
  end if;

  insert into public.staff_invites(
    business_id, role_id, invited_email, token_hash, permission_codes,
    location_id, expires_at, created_by
  )
  values (
    target_business_id, target_role_id, normalized_email,
    encode(digest(token, 'sha256'), 'hex'),
    target_permission_codes,
    target_location_id,
    now() + make_interval(hours => target_expires_hours),
    actor
  )
  returning * into invite;

  insert into public.audit_events(
    business_id, actor_user_id, action, entity_type, entity_id, reason, metadata
  )
  values (
    target_business_id, actor, 'staff_invite_created', 'staff_invite', invite.id,
    'Staff invitation created',
    jsonb_build_object(
      'role_id', target_role_id,
      'invited_email', invite.invited_email,
      'location_id', invite.location_id,
      'expires_at', invite.expires_at
    )
  );

  return jsonb_build_object(
    'invite_id', invite.id,
    'token', token,
    'expires_at', invite.expires_at
  );
end;
$$;

-- The legacy 5-argument contract remains service-role-only; the 4-argument legacy overload is not present in every production history.
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[])
  from public,anon,authenticated,service_role;
grant execute on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[],uuid)
  to service_role;

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
  now_ts timestamptz := now();
begin
  if target_user_id is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;

  select email into account_email
  from auth.users
  where id = target_user_id;

  if account_email is null then
    raise exception using errcode='42501', message='Authenticated account not found';
  end if;

  select * into invite
  from public.staff_invites
  where token_hash = encode(digest(target_token, 'sha256'), 'hex')
  for update;

  if invite.id is null then
    raise exception using errcode='22023', message='Invalid invite';
  end if;
  if invite.claimed_at is not null then
    raise exception using errcode='23505', message='Invite already claimed';
  end if;
  if invite.expires_at <= now_ts then
    raise exception using errcode='22023', message='Invite expired';
  end if;
  if invite.invited_email is not null
     and lower(account_email) <> lower(invite.invited_email) then
    raise exception using errcode='42501',
      message='Invite email does not match the signed-in account';
  end if;

  select * into role_row
  from public.roles
  where id = invite.role_id
    and business_id = invite.business_id;

  if role_row.id is null or role_row.name = 'owner' then
    raise exception using errcode='22023', message='Invite role is no longer valid';
  end if;

  if invite.location_id is not null and not exists (
    select 1
    from public.locations l
    where l.id = invite.location_id
      and l.business_id = invite.business_id
      and l.status = 'active'
  ) then
    raise exception using errcode='22023',
      message='Invite location is no longer active';
  end if;

  select * into membership
  from public.business_memberships
  where business_id = invite.business_id
    and user_id = target_user_id
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
    set role_id = invite.role_id,
        status = 'active',
        joined_at = coalesce(joined_at, now_ts),
        permissions_overridden = invite.permission_codes is not null,
        updated_at = now_ts
    where id = membership.id
    returning * into membership;
  end if;

  delete from public.business_member_permissions
  where business_id = invite.business_id
    and user_id = target_user_id;

  if invite.permission_codes is not null then
    insert into public.business_member_permissions(
      business_id, user_id, permission_id, granted_by, granted_at
    )
    select
      invite.business_id,
      target_user_id,
      p.id,
      invite.created_by,
      now_ts
    from public.permissions p
    where p.code = any(invite.permission_codes);
  end if;

  selected_location_id := invite.location_id;

  if selected_location_id is null then
    select lm.location_id into selected_location_id
    from public.location_memberships lm
    where lm.business_id = invite.business_id
      and lm.user_id = target_user_id
      and lm.status = 'active'
    order by lm.created_at
    limit 1;
  end if;

  if selected_location_id is null then
    select l.id into selected_location_id
    from public.locations l
    where l.business_id = invite.business_id
      and l.status = 'active'
    order by l.created_at
    limit 1;
  end if;

  if selected_location_id is not null then
    insert into public.location_memberships(
      business_id, location_id, user_id, status
    )
    values (
      invite.business_id, selected_location_id, target_user_id, 'active'
    )
    on conflict (location_id, user_id) do update
      set status = 'active', updated_at = now_ts;
  end if;

  select p.full_name into profile_name
  from public.profiles p
  where p.id = target_user_id;

  update public.staff_invites
  set claimed_at = now_ts,
      claimed_by = target_user_id,
      updated_at = now_ts
  where id = invite.id;

  insert into public.audit_events(
    business_id, actor_user_id, action, entity_type, entity_id, metadata
  )
  values (
    invite.business_id, target_user_id, 'staff_invite_claimed',
    'business_membership', membership.id,
    jsonb_build_object(
      'invite_id', invite.id,
      'role_id', invite.role_id,
      'location_id', selected_location_id
    )
  );

  return jsonb_build_object(
    'business_id', membership.business_id,
    'membership_id', membership.id,
    'user_id', target_user_id,
    'role_id', membership.role_id,
    'role_name', role_row.name,
    'full_name', coalesce(nullif(trim(profile_name), ''), ''),
    'email', account_email,
    'location_id', selected_location_id,
    'permission_codes',
      coalesce(
        invite.permission_codes,
        array(
          select p.code
          from public.role_permissions rp
          join public.permissions p on p.id = rp.permission_id
          where rp.role_id = invite.role_id
        )
      )
  );
end;
$claim$;

revoke all on function public.claim_staff_invite(text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.claim_staff_invite(text,uuid)
  to service_role;
