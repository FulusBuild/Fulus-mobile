-- Cross-device employee login and server-authoritative staff access.
-- This migration completes the existing staff-invite skeleton:
-- invitations are created by the service boundary with an explicit actor,
-- claims create/activate a real cloud membership, and per-member permission
-- overrides preserve the exact local access granted by the owner.

alter table public.staff_invites
  add column if not exists permission_codes text[];

alter table public.business_memberships
  add column if not exists permissions_overridden boolean not null default false;

create table if not exists public.business_member_permissions (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (business_id, user_id, permission_id),
  foreign key (business_id, user_id)
    references public.business_memberships(business_id, user_id)
    on delete cascade
);

create index if not exists business_member_permissions_user_idx
  on public.business_member_permissions (business_id, user_id);

alter table public.business_member_permissions enable row level security;

drop policy if exists business_member_permissions_admin_manage
  on public.business_member_permissions;
create policy business_member_permissions_admin_manage
  on public.business_member_permissions
  for all
  using (public.is_business_admin(business_id))
  with check (public.is_business_admin(business_id));

create or replace function public.create_staff_invite(
  target_business_id uuid,
  target_role_id uuid,
  target_email text,
  target_expires_hours integer default 24,
  target_actor_user_id uuid default null,
  target_permission_codes text[] default null
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

  if target_permission_codes is not null and exists (
    select 1
    from unnest(target_permission_codes) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023',
      message='Invite contains an unknown permission';
  end if;

  insert into public.staff_invites(
    business_id, role_id, invited_email, token_hash, permission_codes,
    expires_at, created_by
  )
  values (
    target_business_id, target_role_id, normalized_email,
    encode(digest(token, 'sha256'), 'hex'),
    target_permission_codes,
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

  select lm.location_id into selected_location_id
  from public.location_memberships lm
  where lm.business_id = invite.business_id
    and lm.user_id = target_user_id
    and lm.status = 'active'
  order by lm.created_at
  limit 1;

  if selected_location_id is null then
    select l.id into selected_location_id
    from public.locations l
    where l.business_id = invite.business_id
      and l.status = 'active'
    order by l.created_at
    limit 1;

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
    jsonb_build_object('invite_id', invite.id, 'role_id', invite.role_id)
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
  membership_id uuid;
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
      message='Only an owner or admin may change staff permissions';
  end if;

  select id into membership_id
  from public.business_memberships
  where business_id = target_business_id
    and user_id = target_user_id
    and status = 'active';

  if membership_id is null then
    raise exception using errcode='22023', message='Active staff membership not found';
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_permission_codes, array[]::text[])) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023', message='Unknown permission';
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
  where id = membership_id;

  return true;
end;
$$;

create or replace function public.has_permission(
  target_business_id uuid,
  permission_code text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.business_memberships bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
      and (
        r.name = 'owner'
        or (
          bm.permissions_overridden
          and exists (
            select 1
            from public.business_member_permissions mp
            join public.permissions p on p.id = mp.permission_id
            where mp.business_id = bm.business_id
              and mp.user_id = bm.user_id
              and p.code = permission_code
          )
        )
        or (
          not bm.permissions_overridden
          and exists (
            select 1
            from public.role_permissions rp
            join public.permissions p on p.id = rp.permission_id
            where rp.role_id = bm.role_id
              and p.code = permission_code
          )
        )
      )
  );
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
as $
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
      and r.name in ('owner', 'admin')
  ) then
    raise exception using errcode='42501',
      message='Only an owner or admin may change membership status';
  end if;
  if target_status not in ('active', 'suspended', 'removed') then
    raise exception using errcode='22023', message='Invalid membership status';
  end if;

  select user_id into target_member_user
  from public.business_memberships
  where id = target_membership_id
    and business_id = target_business_id;

  if target_member_user is null then
    return false;
  end if;

  update public.business_memberships
  set status = target_status,
      updated_at = now()
  where id = target_membership_id
    and business_id = target_business_id;

  if target_status <> 'active' then
    update public.devices
    set status = 'revoked', updated_at = now()
    where business_id = target_business_id
      and registered_by = target_member_user
      and status = 'active';
  end if;

  return true;
end;
$;

create or replace function public.change_member_role(
  target_business_id uuid,
  target_membership_id uuid,
  target_role_id uuid,
  target_user_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $
declare
  target_member_user uuid;
  target_role_name text;
begin
  if not public.is_business_admin_for_user(target_business_id, target_user_id) then
    raise exception using errcode='42501',
      message='Only an owner or admin may change member roles';
  end if;

  select name into target_role_name
  from public.roles
  where id = target_role_id
    and business_id = target_business_id;

  if target_role_name is null or target_role_name = 'owner' then
    raise exception using errcode='22023', message='Invalid target role';
  end if;

  select user_id into target_member_user
  from public.business_memberships
  where id = target_membership_id
    and business_id = target_business_id;

  if target_member_user is null then
    return false;
  end if;

  update public.business_memberships
  set role_id = target_role_id,
      permissions_overridden = false,
      updated_at = now()
  where id = target_membership_id;

  delete from public.business_member_permissions
  where business_id = target_business_id
    and user_id = target_member_user;

  return true;
end;
$;

create or replace function public.set_role_permission(
  target_business_id uuid,
  target_role_id uuid,
  target_permission_id uuid,
  enabled boolean,
  target_actor_user_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $
begin
  if not exists (
    select 1
    from public.business_memberships bm
    join public.roles actor_role on actor_role.id = bm.role_id
    where bm.business_id = target_business_id
      and bm.user_id = target_actor_user_id
      and bm.status = 'active'
      and (
        actor_role.name = 'owner'
        or exists (
          select 1
          from public.role_permissions actor_rp
          where actor_rp.role_id = actor_role.id
            and actor_rp.permission_id = target_permission_id
        )
      )
      and exists (
        select 1
        from public.roles target_role
        where target_role.id = target_role_id
          and target_role.business_id = target_business_id
      )
  ) then
    raise exception using errcode='42501',
      message='Permission change is not allowed';
  end if;

  if enabled then
    insert into public.role_permissions(role_id, permission_id)
    values (target_role_id, target_permission_id)
    on conflict do nothing;
  else
    delete from public.role_permissions
    where role_id = target_role_id
      and permission_id = target_permission_id;
  end if;

  return true;
end;
$;

revoke all on function public.is_business_admin_for_user(uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.set_member_status(uuid,uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function public.set_member_status(uuid,uuid,text,uuid) to service_role;
revoke all on function public.change_member_role(uuid,uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.change_member_role(uuid,uuid,uuid,uuid) to service_role;
revoke all on function public.set_role_permission(uuid,uuid,uuid,boolean,uuid)
  from public,anon,authenticated;
grant execute on function public.set_role_permission(uuid,uuid,uuid,boolean,uuid) to service_role;

revoke all on function public.create_staff_invite(uuid,uuid,text,integer) from public,anon,authenticated;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid) from public,anon,authenticated,service_role;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[]) from public,anon,authenticated;
grant execute on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[]) to service_role;

revoke all on function public.claim_staff_invite(text) from public,anon,authenticated;
revoke all on function public.claim_staff_invite(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.claim_staff_invite(text,uuid) to service_role;

revoke all on function public.set_member_permission_overrides(uuid,uuid,text[],uuid)
  from public,anon,authenticated;
grant execute on function public.set_member_permission_overrides(uuid,uuid,text[],uuid)
  to service_role;

revoke all on function public.has_permission(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.has_permission(uuid,text)
  to authenticated, service_role;
