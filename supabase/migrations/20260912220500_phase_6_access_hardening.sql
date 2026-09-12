-- Phase 6 access hardening: owner protection, device audit and device-user binding.
create or replace function public.is_business_owner(target_business_id uuid)
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists (
    select 1 from public.business_memberships bm
    join public.roles r on r.id=bm.role_id
    where bm.business_id=target_business_id and bm.user_id=auth.uid()
      and bm.status='active' and r.name='owner'
  );
$$;

create or replace function public.set_member_status(
  target_business_id uuid,target_membership_id uuid,target_status text
) returns boolean language plpgsql security definer set search_path=public
as $$
declare target_user uuid; target_role text;
begin
  if not public.is_business_admin(target_business_id) then raise exception using errcode='42501',message='Only an owner or admin may change membership status'; end if;
  if target_status not in ('active','suspended','removed') then raise exception using errcode='22023',message='Invalid membership status'; end if;
  select bm.user_id,r.name into target_user,target_role from public.business_memberships bm join public.roles r on r.id=bm.role_id where bm.id=target_membership_id and bm.business_id=target_business_id;
  if target_user is null then return false; end if;
  if target_role='owner' then raise exception using errcode='42501',message='The owner membership cannot be suspended or removed'; end if;
  update public.business_memberships set status=target_status,joined_at=case when target_status='active' then coalesce(joined_at,now()) else joined_at end,updated_at=now() where id=target_membership_id and business_id=target_business_id;
  if target_status <> 'active' then update public.devices set status='revoked',updated_at=now() where business_id=target_business_id and registered_by=target_user and status='active'; end if;
  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata) values(target_business_id,auth.uid(),'member_status_changed','business_membership',target_membership_id,jsonb_build_object('user_id',target_user,'status',target_status));
  return true;
end; $$;

create or replace function public.change_member_role(
  target_business_id uuid,target_membership_id uuid,target_role_id uuid
) returns boolean language plpgsql security definer set search_path=public
as $$
declare target_user uuid; current_role text; new_role text;
begin
  if not public.is_business_admin(target_business_id) then raise exception using errcode='42501',message='Only an owner or admin may change member roles'; end if;
  select name into new_role from public.roles where business_id=target_business_id and id=target_role_id;
  if new_role is null or new_role='owner' then raise exception using errcode='22023',message='Invalid target role'; end if;
  select bm.user_id,r.name into target_user,current_role from public.business_memberships bm join public.roles r on r.id=bm.role_id where bm.id=target_membership_id and bm.business_id=target_business_id;
  if target_user is null then return false; end if;
  if current_role='owner' then raise exception using errcode='42501',message='The owner role cannot be changed here'; end if;
  if current_role='admin' or new_role='admin' then
    if not public.is_business_owner(target_business_id) then raise exception using errcode='42501',message='Only the owner may grant or remove admin access'; end if;
  end if;
  update public.business_memberships set role_id=target_role_id,updated_at=now() where id=target_membership_id;
  insert into public.audit_events(business_id,actor_user_id,action,entity_type,entity_id,metadata) values(target_business_id,auth.uid(),'member_role_changed','business_membership',target_membership_id,jsonb_build_object('user_id',target_user,'from_role',current_role,'to_role',new_role));
  return true;
end; $$;

create or replace function public.revoke_device(
  target_business_id uuid,target_device_id uuid,target_user_id uuid
) returns boolean language plpgsql security definer set search_path=public
as $$
declare revoked_user uuid;
begin
  if not public.is_business_admin(target_business_id) then raise exception using errcode='42501',message='Only an owner or admin may revoke devices'; end if;
  select registered_by into revoked_user from public.devices where id=target_device_id and business_id=target_business_id;
  if revoked_user is null then return false; end if;
  update public.devices set status='revoked',updated_at=now() where id=target_device_id and business_id=target_business_id;
  insert into public.audit_events(business_id,actor_user_id,device_id,action,entity_type,entity_id,metadata) values(target_business_id,auth.uid(),target_device_id,'device_revoked','device',target_device_id,jsonb_build_object('registered_by',revoked_user));
  return true;
end; $$;

create or replace function public.register_device(
  target_business_id uuid,target_user_id uuid,target_device_client_id text,target_device_name text,target_platform text,target_app_version text
) returns public.devices language plpgsql security definer set search_path=public
as $$
declare result public.devices;
begin
  if target_device_client_id is null or length(trim(target_device_client_id)) < 8 then raise exception using errcode='22023',message='device_client_id must be at least 8 characters'; end if;
  if target_user_id <> auth.uid() then raise exception using errcode='42501',message='A device may only be registered for the signed-in user'; end if;
  if not exists(select 1 from public.business_memberships where business_id=target_business_id and user_id=target_user_id and status='active') then raise exception using errcode='42501',message='User is not an active member of this business'; end if;
  insert into public.devices(business_id,registered_by,device_client_id,device_name,platform,app_version,status,last_seen_at) values(target_business_id,target_user_id,trim(target_device_client_id),target_device_name,target_platform,target_app_version,'active',now())
  on conflict(business_id,device_client_id) do update set registered_by=excluded.registered_by,device_name=excluded.device_name,platform=excluded.platform,app_version=excluded.app_version,status='active',last_seen_at=now(),updated_at=now()
  returning * into result;
  insert into public.audit_events(business_id,actor_user_id,device_id,action,entity_type,entity_id,metadata) values(target_business_id,auth.uid(),result.id,'device_registered','device',result.id,jsonb_build_object('device_client_id',result.device_client_id,'platform',result.platform));
  return result;
end; $$;