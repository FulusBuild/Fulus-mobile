-- Cloud Sync V1 hardening: enforce idempotency scope centrally.
-- Every idempotency record must be bound to the business, device, and user
-- that first used the operation key. The guard also serializes competing
-- first-use attempts so a concurrent cross-device replay cannot slip through
-- an application-level ON CONFLICT DO NOTHING.

create or replace function public._fulus_guard_idempotency_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $func$
declare
  existing public.idempotency_keys%rowtype;
begin
  if new.business_id is null
     or new.device_id is null
     or new.user_id is null
     or new.key is null
     or length(trim(new.key)) = 0 then
    raise exception using
      errcode='22023',
      message='Idempotency records require business, device, user, and key scope';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      new.business_id::text || ':' || new.key,
      0
    )
  );

  select * into existing
  from public.idempotency_keys
  where business_id = new.business_id
    and key = new.key
  for update;

  if found and (
    existing.device_id is distinct from new.device_id
    or existing.user_id is distinct from new.user_id
  ) then
    raise exception using
      errcode='P0009',
      message='Operation id was already used from a different device or account';
  end if;

  return new;
end;
$func$;

drop trigger if exists trg_fulus_idempotency_scope_guard
on public.idempotency_keys;

create trigger trg_fulus_idempotency_scope_guard
before insert on public.idempotency_keys
for each row
execute function public._fulus_guard_idempotency_scope();

revoke all on function public._fulus_guard_idempotency_scope()
from public, anon, authenticated;
grant execute on function public._fulus_guard_idempotency_scope()
to service_role;
