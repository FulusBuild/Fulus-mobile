-- Harden staff permission delegation at the server boundary.
-- UI restrictions are not sufficient: owner/admin clients can call the
-- staff Edge Function directly, so the database must enforce that an actor
-- cannot grant permissions they do not themselves hold.

create or replace function public.staff_actor_has_permission(
  target_business_id uuid,
  target_actor_user_id uuid,
  target_permission_code text
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
      and bm.user_id = target_actor_user_id
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
              and p.code = target_permission_code
          )
        )
        or (
          not bm.permissions_overridden
          and exists (
            select 1
            from public.role_permissions rp
            join public.permissions p on p.id = rp.permission_id
            where rp.role_id = bm.role_id
              and p.code = target_permission_code
          )
        )
      )
  );
$$;

revoke all on function public.staff_actor_has_permission(uuid,uuid,text)
  from public, anon, authenticated, service_role;

-- Only the security-definer staff RPCs need this helper.
grant execute on function public.staff_actor_has_permission(uuid,uuid,text)
  to service_role;

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
      and r.name in ('owner', 'admin')
  ) then
    raise exception using errcode='42501',
      message='Only an owner or admin may change staff permissions';
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
    from unnest(coalesce(target_permission_codes, array[]::text[])) code
    left join public.permissions p on p.code = code
    where p.id is null
  ) then
    raise exception using errcode='22023', message='Unknown permission';
  end if;

  -- Match the local permission-editor invariant: an admin may only add or
  -- remove permissions they themselves hold. Existing permissions outside
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

revoke all on function public.create_staff_invite(uuid,uuid,text,integer)
  from public,anon,authenticated;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[])
  from public,anon,authenticated;
grant execute on function public.create_staff_invite(uuid,uuid,text,integer,uuid,text[])
  to service_role;

revoke all on function public.set_member_permission_overrides(uuid,uuid,text[],uuid)
  from public,anon,authenticated;
grant execute on function public.set_member_permission_overrides(uuid,uuid,text[],uuid)
  to service_role;
