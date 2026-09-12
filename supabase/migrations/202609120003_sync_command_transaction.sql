create or replace function public.accept_sync_operation(
  target_business_id uuid,
  target_device_id uuid,
  target_user_id uuid,
  target_operation_id text,
  target_operation_type text,
  target_client_reference text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_idem public.idempotency_keys%rowtype;
  new_operation_id uuid;
  response jsonb;
begin
  if not exists (
    select 1 from public.business_memberships
    where business_id = target_business_id
      and user_id = target_user_id
      and status = 'active'
  ) then
    return jsonb_build_object(
      'status_code', 403,
      'error', jsonb_build_object('code','FORBIDDEN','message','User is not an active member of this business')
    );
  end if;

  if not exists (
    select 1 from public.devices
    where id = target_device_id
      and business_id = target_business_id
      and status = 'active'
  ) then
    return jsonb_build_object(
      'status_code', 403,
      'error', jsonb_build_object('code','DEVICE_NOT_REGISTERED','message','Device is not registered or active')
    );
  end if;

  insert into public.idempotency_keys (
    business_id, device_id, user_id, key, operation_type, request_hash
  )
  values (
    target_business_id, target_device_id, target_user_id,
    target_operation_id, target_operation_type, target_request_hash
  )
  on conflict (business_id, key) do nothing;

  select * into existing_idem
  from public.idempotency_keys
  where business_id = target_business_id
    and key = target_operation_id;

  if existing_idem.operation_type <> target_operation_type
     or existing_idem.request_hash <> target_request_hash then
    return jsonb_build_object(
      'status_code', 409,
      'error', jsonb_build_object('code','IDEMPOTENCY_CONFLICT','message','Operation id was already used with a different request')
    );
  end if;

  if existing_idem.completed_at is not null
     and existing_idem.response_body is not null then
    return jsonb_build_object(
      'status_code', coalesce(existing_idem.response_status, 200),
      'response', existing_idem.response_body
    );
  end if;

  insert into public.sync_operations (
    business_id, device_id, user_id, operation_id,
    operation_type, client_reference, status
  )
  values (
    target_business_id, target_device_id, target_user_id, target_operation_id,
    target_operation_type, target_client_reference, 'received'
  )
  on conflict (business_id, device_id, operation_id) do nothing
  returning id into new_operation_id;

  if new_operation_id is null then
    select * into existing_idem
    from public.idempotency_keys
    where business_id = target_business_id
      and key = target_operation_id;
  end if;

  response := jsonb_build_object(
    'data', jsonb_build_object(
      'accepted', true,
      'operation_id', target_operation_id,
      'server_operation_id', coalesce(new_operation_id, existing_idem.id),
      'status', 'received',
      'server_authoritative', true
    )
  );

  update public.idempotency_keys
  set response_status = 202,
      response_body = response,
      completed_at = now()
  where id = existing_idem.id;

  return jsonb_build_object('status_code', 202, 'response', response);
end;
$$;

revoke execute on function public.accept_sync_operation(uuid, uuid, uuid, text, text, text, text)
from public, anon, authenticated;
