-- Require the active device to belong to the authenticated user for
-- return, income, and cash-drawer action wrappers.
-- This prevents a service-role action request from attributing a mutation
-- to an arbitrary device UUID.
create or replace function public.fulus_api_create_return_atomic(target_user_id uuid,target_business_id uuid,target_sale_id uuid,target_client_reference text,target_reason text,target_refund_amount numeric,target_device_id uuid,target_items jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare item jsonb; normalized_items jsonb:='[]'::jsonb; resolved_sale_item_id uuid; match_count integer;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then
    raise exception using errcode='42501',message='Device is not registered or active';
  end if;
  if target_items is null or jsonb_array_length(target_items)=0 then
    return public.create_return_atomic(target_business_id,target_sale_id,target_client_reference,target_reason,target_refund_amount,target_device_id,target_items);
  end if;
  for item in select * from jsonb_array_elements(target_items) loop
    if nullif(trim(item->>'sale_item_id'),'') is not null then
      normalized_items:=normalized_items||jsonb_build_array(item);
    elsif nullif(trim(item->>'product_id'),'') is not null then
      resolved_sale_item_id:=null; match_count:=0;
      select count(*)::integer,(array_agg(si.id))[1] into match_count,resolved_sale_item_id
      from public.sale_items si join public.sales s on s.id=si.sale_id
      where si.sale_id=target_sale_id and si.product_id=(item->>'product_id')::uuid and s.business_id=target_business_id;
      if match_count<>1 then raise exception using errcode='22023',message='Return product must identify exactly one sale item'; end if;
      normalized_items:=normalized_items||jsonb_build_array(jsonb_build_object('sale_item_id',resolved_sale_item_id,'quantity',(item->>'quantity')::integer));
    else
      raise exception using errcode='22023',message='Return item requires sale_item_id or product_id';
    end if;
  end loop;
  return public.create_return_atomic(target_business_id,target_sale_id,target_client_reference,target_reason,target_refund_amount,target_device_id,normalized_items);
end;$function$;

create or replace function public.fulus_api_cloud_record_income(target_user_id uuid,target_business_id uuid,target_location_id uuid,target_source text,target_amount numeric,target_income_date timestamptz,target_notes text,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
  if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
  request_hash:=md5(jsonb_build_object('location_id',target_location_id,'source',target_source,'amount',target_amount,'income_date',target_income_date,'notes',target_notes,'device_id',target_device_id)::text);
  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'income.create',request_hash) on conflict(business_id,key) do nothing;
  select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
  if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
  if idem.operation_type<>'income.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  result:=public.cloud_record_income(target_business_id,target_location_id,target_source,target_amount,target_income_date,target_notes,target_operation_id,target_device_id);
  update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
  return result;
end;$function$;

create or replace function public.fulus_api_cloud_open_cash_drawer_shift(target_user_id uuid,target_business_id uuid,target_location_id uuid,target_opening_cash numeric,target_opened_at timestamptz,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
  if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
  request_hash:=md5(jsonb_build_object('location_id',target_location_id,'opening_cash',target_opening_cash,'opened_at',target_opened_at,'device_id',target_device_id)::text);
  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'cash_drawer_shift.create',request_hash) on conflict(business_id,key) do nothing;
  select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
  if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
  if idem.operation_type<>'cash_drawer_shift.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  result:=public.cloud_open_cash_drawer_shift(target_business_id,target_location_id,target_opening_cash,target_opened_at,target_operation_id,target_device_id);
  update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
  return result;
end;$function$;

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(target_user_id uuid,target_business_id uuid,target_shift_id uuid,target_closing_cash numeric,target_cash_difference numeric,target_closing_note text,target_closed_at timestamptz,target_operation_id text,target_device_id uuid,target_base_cursor bigint)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
  if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
  request_hash:=md5(jsonb_build_object('shift_id',target_shift_id,'closing_cash',target_closing_cash,'cash_difference',target_cash_difference,'closing_note',target_closing_note,'closed_at',target_closed_at,'device_id',target_device_id,'base_cursor',target_base_cursor)::text);
  insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'cash_drawer_shift.close',request_hash) on conflict(business_id,key) do nothing;
  select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
  if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
  if idem.operation_type<>'cash_drawer_shift.close' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
  if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  result:=public.cloud_close_cash_drawer_shift(target_business_id,target_shift_id,target_closing_cash,target_cash_difference,target_closing_note,target_closed_at,target_operation_id,target_device_id,target_base_cursor);
  update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
  return result;
end;$function$;