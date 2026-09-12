create or replace function public.register_device(
  target_business_id uuid,
  target_user_id uuid,
  target_device_client_id text,
  target_device_name text,
  target_platform text,
  target_app_version text
)
returns public.devices
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.devices;
begin
  if target_device_client_id is null or length(trim(target_device_client_id)) < 8 then
    raise exception using errcode='22023', message='device_client_id must be at least 8 characters';
  end if;
  if not exists (
    select 1 from public.business_memberships
    where business_id=target_business_id and user_id=target_user_id and status='active'
  ) then
    raise exception using errcode='42501', message='User is not an active member of this business';
  end if;

  insert into public.devices (business_id, registered_by, device_client_id, device_name, platform, app_version, status, last_seen_at)
  values (target_business_id,target_user_id,trim(target_device_client_id),target_device_name,target_platform,target_app_version,'active',now())
  on conflict (business_id,device_client_id)
  do update set registered_by=excluded.registered_by, device_name=excluded.device_name,
    platform=excluded.platform, app_version=excluded.app_version, status='active',
    last_seen_at=now(), updated_at=now()
  returning * into result;
  return result;
end;
$$;

create or replace function public.revoke_device(
  target_business_id uuid,
  target_device_id uuid,
  target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.business_memberships bm
    join public.roles r on r.id=bm.role_id
    where bm.business_id=target_business_id and bm.user_id=target_user_id
      and bm.status='active' and r.name in ('owner','admin')
  ) then
    raise exception using errcode='42501', message='Only an owner or admin may revoke devices';
  end if;
  update public.devices set status='revoked', updated_at=now()
  where id=target_device_id and business_id=target_business_id;
  return found;
end;
$$;

revoke execute on function public.register_device(uuid,uuid,text,text,text,text) from public,anon,authenticated;
revoke execute on function public.revoke_device(uuid,uuid,uuid) from public,anon,authenticated;
