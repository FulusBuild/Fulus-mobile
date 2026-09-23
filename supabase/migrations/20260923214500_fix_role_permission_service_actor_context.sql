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
as $$
begin
  if not exists(
    select 1
    from public.business_memberships bm
    join public.roles r on r.id=bm.role_id
    where bm.business_id=target_business_id
      and bm.user_id=target_actor_user_id
      and bm.status='active'
      and r.name in ('owner','admin')
  ) then
    raise exception using errcode='42501',message='Only an owner or admin may change role permissions';
  end if;

  perform set_config('request.jwt.claim.sub', target_actor_user_id::text, true);

  if not public.can_manage_role_permission(
    target_business_id,target_role_id,target_permission_id
  ) then
    raise exception using errcode='42501',message='Permission change is not allowed';
  end if;

  if enabled then
    insert into public.role_permissions(role_id,permission_id)
    values(target_role_id,target_permission_id)
    on conflict do nothing;
  else
    delete from public.role_permissions
    where role_id=target_role_id
      and permission_id=target_permission_id;
  end if;

  insert into public.audit_events(
    business_id,actor_user_id,action,entity_type,entity_id,metadata
  )
  values(
    target_business_id,target_actor_user_id,'role_permission_changed',
    'role',target_role_id,
    jsonb_build_object('permission_id',target_permission_id,'enabled',enabled)
  );
  return true;
end;
$$;

revoke execute on function public.can_manage_role_permission(uuid,uuid,uuid)
from service_role, public, anon, authenticated;
