-- Route the Edge Function's optimistic-concurrency cursor through the service wrapper.
-- The older wrapper overload remains only for legacy callers; the cloud API must
-- use the base-cursor-aware signature so close operations cannot bypass conflicts.

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(
  target_user_id uuid,
  target_business_id uuid,
  target_shift_id uuid,
  target_closing_cash numeric,
  target_cash_difference numeric,
  target_closing_note text,
  target_closed_at timestamptz,
  target_operation_id text,
  target_device_id uuid,
  target_base_cursor bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.cloud_close_cash_drawer_shift(
    target_business_id,
    target_shift_id,
    target_closing_cash,
    target_cash_difference,
    target_closing_note,
    target_closed_at,
    target_operation_id,
    target_device_id,
    target_base_cursor
  );
end;
$$;

revoke all on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid
) from public, anon, authenticated;
revoke all on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint
) from public, anon, authenticated;
grant execute on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint
) to service_role;
