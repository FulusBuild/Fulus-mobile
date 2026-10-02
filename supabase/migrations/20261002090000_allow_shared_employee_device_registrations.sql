-- A physical phone can be used by more than one employee account.
-- Device authorization remains actor-scoped: each employee gets their own
-- registration row, so pending offline work from employee A can still drain
-- after employee B signs into the same phone without reusing B's device grant.

alter table public.devices
  drop constraint if exists devices_business_id_device_client_id_key;

alter table public.devices
  add constraint devices_business_device_actor_key
  unique (business_id, device_client_id, registered_by);

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
  if target_device_client_id is null
     or length(trim(target_device_client_id)) < 8 then
    raise exception using errcode='22023',
      message='device_client_id must be at least 8 characters';
  end if;

  if not exists (
    select 1
    from public.business_memberships
    where business_id = target_business_id
      and user_id = target_user_id
      and status = 'active'
  ) then
    raise exception using errcode='42501',
      message='User is not an active member of this business';
  end if;

  insert into public.devices (
    business_id,
    registered_by,
    device_client_id,
    device_name,
    platform,
    app_version,
    status,
    last_seen_at
  )
  values (
    target_business_id,
    target_user_id,
    trim(target_device_client_id),
    target_device_name,
    target_platform,
    target_app_version,
    'active',
    now()
  )
  on conflict (business_id, device_client_id, registered_by)
  do update set
    device_name = excluded.device_name,
    platform = excluded.platform,
    app_version = excluded.app_version,
    status = 'active',
    last_seen_at = now(),
    updated_at = now()
  returning * into result;

  return result;
end;
$$;

revoke execute on function public.register_device(uuid,uuid,text,text,text,text)
  from public, anon, authenticated;
