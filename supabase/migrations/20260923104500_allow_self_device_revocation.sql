-- Allow a signed-in user to revoke an ephemeral/own device they registered.
-- Administrative device revocation remains owner/admin-only via revoke_device.
create or replace function public.fulus_api_revoke_own_device(
  target_user_id uuid,
  target_business_id uuid,
  target_device_id uuid
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare revoked boolean := false;
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  if target_user_id <> auth.uid() then
    raise exception using errcode='42501',message='Authentication required';
  end if;

  update public.devices
  set status='revoked', updated_at=now()
  where id=target_device_id
    and business_id=target_business_id
    and registered_by=target_user_id
    and status='active';

  revoked := found;

  if revoked then
    insert into public.audit_events(
      business_id,actor_user_id,device_id,action,entity_type,entity_id,metadata
    )
    values(
      target_business_id,target_user_id,target_device_id,
      'device_revoked','device',target_device_id,
      jsonb_build_object('self_revoked',true)
    );
  end if;

  return revoked;
end;
$$;

revoke all on function public.fulus_api_revoke_own_device(uuid,uuid,uuid)
from public, anon, authenticated;
grant execute on function public.fulus_api_revoke_own_device(uuid,uuid,uuid)
to service_role;
