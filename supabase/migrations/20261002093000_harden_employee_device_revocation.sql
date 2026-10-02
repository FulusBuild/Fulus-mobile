-- Staff device revocation is called through the trusted staff API with an
-- explicit actor user id. Do not depend on auth.uid() being populated by a
-- service-role client; the actor was already authenticated by the Edge Function.

create or replace function public.revoke_device(
  target_business_id uuid,
  target_device_id uuid,
  target_user_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  revoked_user uuid;
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
      message='Only an owner or admin may revoke devices';
  end if;

  select registered_by
    into revoked_user
  from public.devices
  where id = target_device_id
    and business_id = target_business_id;

  if revoked_user is null then
    return false;
  end if;

  update public.devices
  set status = 'revoked',
      updated_at = now()
  where id = target_device_id
    and business_id = target_business_id;

  insert into public.audit_events(
    business_id, actor_user_id, device_id, action, entity_type, entity_id, metadata
  )
  values (
    target_business_id, target_user_id, target_device_id, 'device_revoked',
    'device', target_device_id,
    jsonb_build_object('registered_by', revoked_user)
  );

  return true;
end;
$$;

revoke all on function public.revoke_device(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.revoke_device(uuid,uuid,uuid)
  to service_role;
