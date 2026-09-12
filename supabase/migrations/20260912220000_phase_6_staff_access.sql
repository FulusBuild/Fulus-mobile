-- Phase 6: staff access, invitations, role changes and device/session revocation.
-- This migration is intentionally idempotent so it can be replayed safely in a
-- fresh Fulus environment and remains compatible with the already-applied live DB.

create table if not exists public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  role_id uuid not null,
  invited_email text,
  token_hash text not null unique,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_by uuid references auth.users(id),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_invites_role_fk foreign key (business_id, role_id)
    references public.roles(business_id, id),
  constraint staff_invites_claim_check check (
    (claimed_at is null and claimed_by is null) or
    (claimed_at is not null and claimed_by is not null)
  )
);

create index if not exists staff_invites_business_status_idx
  on public.staff_invites (business_id, expires_at, claimed_at);
create unique index if not exists staff_invites_open_email_idx
  on public.staff_invites (business_id, lower(invited_email))
  where invited_email is not null and claimed_at is null;

alter table public.staff_invites enable row level security;

drop policy if exists staff_invites_admin_manage on public.staff_invites;
create policy staff_invites_admin_manage on public.staff_invites
  for all using (public.is_business_admin(business_id))
  with check (public.is_business_admin(business_id));

create or replace function public.create_staff_invite(
  target_business_id uuid,
  target_role_id uuid,
  target_email text default null,
  target_expires_hours integer default 24
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
declare invite public.staff_invites;
begin
  if not public.is_business_admin(target_business_id) then
    raise exception using errcode='42501', message='Only an owner or admin may create staff invites';
  end if;
  if target_expires_hours < 1 or target_expires_hours > 168 then
    raise exception using errcode='22023', message='Invite expiry must be between 1 and 168 hours';
  end if;
  if not exists (
    select 1 from public.roles r
    where r.business_id=target_business_id and r.id=target_role_id and r.name <> 'owner'
  ) then
    raise exception using errcode='22023', message='Invalid staff role';
  end if;
  insert into public.staff_invites(business_id,role_id,invited_email,token_hash,expires_at,created_by)
  values (
    target_business_id,target_role_id,nullif(lower(trim(target_email)), ''),
    encode(digest(token,'sha256'),'hex'),
    now() + make_interval(hours => target_expires_hours),auth.uid()
  ) returning * into invite;
  insert into public.audit_events(
    business_id,actor_user_id,action,entity_type,entity_id,reason,metadata
  ) values (
    target_business_id,auth.uid(),'staff_invite_created','staff_invite',invite.id,
    'Staff invitation created',
    jsonb_build_object('role_id',target_role_id,'invited_email',invite.invited_email,'expires_at',invite.expires_at)
  );
  return jsonb_build_object(
    'invite_id',invite.id,'token',token,'expires_at',invite.expires_at
  );
end;
$$;

create or replace function public.claim_staff_invite(target_token text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare invite public.staff_invites;
declare membership public.business_memberships;
declare now_ts timestamptz := now();
declare account_email text;
begin
  if auth.uid() is null then
    raise exception using errcode='42501', message='Authentication required';
  end if;
  select * into invite from public.staff_invites
    where token_hash=encode(digest(target_token,'sha256'),'hex') for update;
  if invite.id is null then
    raise exception using errcode='22023', message='Invalid invite';
  end if;
  if invite.claimed_at is not null then
    raise exception using errcode='23505', message='Invite already claimed';
  end if;
  if invite.expires_at <= now_ts then
    raise exception using errcode='22023', message='Invite expired';
  end if;
  select email into account_email from auth.users where id=auth.uid();
  if invite.invited_email is not null and lower(coalesce(account_email,'')) <> invite.invited_email then
    raise exception using errcode='42501', message='Invite email does not match signed-in account';
  end if;

  select * into membership from public.business_memberships
    where business_id=invite.business_id and user_id=auth.uid() for update;

  if membership.id is null then
    insert into public.business_memberships(business_id,user_id,role_id,status,joined_at)
      values(invite.business_id,auth.uid(),invite.role_id,'active',now_ts)
      returning * into membership;
  else
    update public.business_memberships
      set role_id=invite.role_id,status='active',joined_at=coalesce(joined_at,now_ts),updated_at=now_ts
      where id=membership.id returning * into membership;
  end if;

  update public.staff_invites
    set claimed_at=now_ts,claimed_by=auth.uid(),updated_at=now_ts where id=invite.id;

  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(
      invite.business_id,auth.uid(),'staff_invite_claimed','business_membership',membership.id,
      jsonb_build_object('invite_id',invite.id,'role_id',invite.role_id)
    );

  return jsonb_build_object(
    'business_id',membership.business_id,
    'membership_id',membership.id,
    'role_id',membership.role_id
  );
end;
$$;

create or replace function public.set_member_status(
  target_business_id uuid,
  target_membership_id uuid,
  target_status text
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
begin
  if not public.is_business_admin(target_business_id) then
    raise exception using errcode='42501',message='Only an owner or admin may change membership status';
  end if;
  if target_status not in ('active','suspended','removed') then
    raise exception using errcode='22023',message='Invalid membership status';
  end if;
  select user_id into target_user from public.business_memberships
    where id=target_membership_id and business_id=target_business_id;
  if target_user is null then return false; end if;

  update public.business_memberships
    set status=target_status,
        joined_at=case when target_status='active' then coalesce(joined_at,now()) else joined_at end,
        updated_at=now()
    where id=target_membership_id and business_id=target_business_id;

  if target_status <> 'active' then
    update public.devices set status='revoked',updated_at=now()
      where business_id=target_business_id and registered_by=target_user and status='active';
  end if;

  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(
      target_business_id,auth.uid(),'member_status_changed','business_membership',target_membership_id,
      jsonb_build_object('user_id',target_user,'status',target_status)
    );
  return true;
end;
$$;

create or replace function public.change_member_role(
  target_business_id uuid,
  target_membership_id uuid,
  target_role_id uuid
) returns boolean
language plpgsql security definer set search_path = public
as $$
declare target_user uuid;
declare role_name text;
begin
  if not public.is_business_admin(target_business_id) then
    raise exception using errcode='42501',message='Only an owner or admin may change member roles';
  end if;
  select name into role_name from public.roles
    where business_id=target_business_id and id=target_role_id;
  if role_name is null or role_name='owner' then
    raise exception using errcode='22023',message='Invalid target role';
  end if;
  select user_id into target_user from public.business_memberships
    where id=target_membership_id and business_id=target_business_id;
  if target_user is null then return false; end if;

  update public.business_memberships set role_id=target_role_id,updated_at=now()
    where id=target_membership_id;

  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(
      target_business_id,auth.uid(),'member_role_changed','business_membership',target_membership_id,
      jsonb_build_object('user_id',target_user,'role_id',target_role_id)
    );
  return true;
end;
$$;

create or replace function public.set_role_permission(
  target_business_id uuid,
  target_role_id uuid,
  target_permission_id uuid,
  enabled boolean
) returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_manage_role_permission(
    target_business_id,target_role_id,target_permission_id
  ) then
    raise exception using errcode='42501',message='Permission change is not allowed';
  end if;

  if enabled then
    insert into public.role_permissions(role_id,permission_id)
      values(target_role_id,target_permission_id) on conflict do nothing;
  else
    delete from public.role_permissions
      where role_id=target_role_id and permission_id=target_permission_id;
  end if;

  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(
      target_business_id,auth.uid(),'role_permission_changed','role',target_role_id,
      jsonb_build_object('permission_id',target_permission_id,'enabled',enabled)
    );
  return true;
end;
$$;

revoke all on function public.create_staff_invite(uuid,uuid,text,integer) from public;
grant execute on function public.create_staff_invite(uuid,uuid,text,integer) to authenticated;
revoke all on function public.claim_staff_invite(text) from public;
grant execute on function public.claim_staff_invite(text) to authenticated;
revoke all on function public.set_member_status(uuid,uuid,text) from public;
grant execute on function public.set_member_status(uuid,uuid,text) to authenticated;
revoke all on function public.change_member_role(uuid,uuid,uuid) from public;
grant execute on function public.change_member_role(uuid,uuid,uuid) to authenticated;
revoke all on function public.set_role_permission(uuid,uuid,uuid,boolean) from public;
grant execute on function public.set_role_permission(uuid,uuid,uuid,boolean) to authenticated;