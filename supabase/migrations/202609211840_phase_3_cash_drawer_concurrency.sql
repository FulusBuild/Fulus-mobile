create or replace function public.cloud_close_cash_drawer_shift(
  target_business_id uuid, target_shift_id uuid, target_closing_cash numeric,
  target_cash_difference numeric, target_closing_note text,
  target_closed_at timestamptz, target_operation_id text,
  target_device_id uuid, target_base_cursor bigint
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare actor uuid:=auth.uid(); existing public.cash_drawer_shifts; updated public.cash_drawer_shifts;
begin
  if actor is null then raise exception using errcode='42501',message='Authentication required'; end if;
  if not public.has_permission(target_business_id,'cash.manage') then raise exception using errcode='42501',message='Cash permission required'; end if;
  if target_operation_id is null or length(trim(target_operation_id))=0 then raise exception using errcode='22023',message='operation_id is required'; end if;
  if target_closing_cash is null or target_closing_cash<0 then raise exception using errcode='22013',message='Closing cash must be non-negative'; end if;

  select * into existing from public.cash_drawer_shifts
  where business_id=target_business_id and close_operation_id=target_operation_id;
  if found then return jsonb_build_object('status','already_applied','id',existing.id,'shift_id',existing.id); end if;

  select * into existing from public.cash_drawer_shifts
  where id=target_shift_id and business_id=target_business_id;
  if not found then raise exception using errcode='P0002',message='Cash drawer shift not found'; end if;
  if existing.closed_at is not null then raise exception using errcode='22013',message='Cash drawer shift is already closed'; end if;

  if target_base_cursor is not null and exists (
    select 1 from public.sync_changes
    where business_id=target_business_id
      and entity_type='cash_drawer_shift'
      and entity_id=target_shift_id
      and sequence > target_base_cursor
  ) then
    raise exception using errcode='P0008',
      message='SYNC_CONFLICT: Cash drawer shift changed on another device after this close was created';
  end if;

  update public.cash_drawer_shifts
  set closed_at=target_closed_at,closing_cash=target_closing_cash,
      cash_difference=target_cash_difference,
      closing_note=nullif(trim(target_closing_note),''),
      closing_summary_locked=true,close_operation_id=target_operation_id,
      device_id=coalesce(target_device_id,device_id),updated_at=now()
  where id=target_shift_id
  returning * into updated;

  perform public._fulus_append_change(
    target_business_id,'cash_drawer_shift',updated.id,'upsert',
    jsonb_build_object(
      'id',updated.id,'cashier_user_id',updated.cashier_user_id,
      'location_id',updated.location_id,'opened_at',updated.opened_at,
      'closed_at',updated.closed_at,'opening_cash',updated.opening_cash,
      'closing_cash',updated.closing_cash,'cash_difference',updated.cash_difference,
      'closing_note',updated.closing_note,'closing_summary_locked',updated.closing_summary_locked
    )
  );
  return jsonb_build_object('status','updated','id',updated.id,'shift_id',updated.id);
end;
$$;

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(
  target_user_id uuid, target_business_id uuid, target_shift_id uuid,
  target_closing_cash numeric, target_cash_difference numeric,
  target_closing_note text, target_closed_at timestamptz,
  target_operation_id text, target_device_id uuid, target_base_cursor bigint
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.cloud_close_cash_drawer_shift(
    target_business_id,target_shift_id,target_closing_cash,target_cash_difference,
    target_closing_note,target_closed_at,target_operation_id,target_device_id,
    target_base_cursor
  );
end;
$$;

revoke execute on function public.cloud_close_cash_drawer_shift(
  uuid,uuid,numeric,numeric,text,timestamptz,text,uuid
) from PUBLIC,anon,authenticated;
revoke execute on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid
) from PUBLIC,anon,authenticated;
grant execute on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint
) to service_role;
revoke execute on function public.fulus_api_cloud_close_cash_drawer_shift(
  uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint
) from PUBLIC,anon,authenticated;