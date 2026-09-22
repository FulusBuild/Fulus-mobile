-- Cloud Sync V1: make legacy action RPCs payload-sensitive idempotent.
-- These wrappers are the single service-role boundary used by fulus-api.
-- Keeping the idempotency claim in the same transaction as the underlying
-- mutation means a failed mutation rolls the claim back as well.

create or replace function public.fulus_api_create_sale_atomic(
 target_user_id uuid,target_business_id uuid,target_location_id uuid,target_customer_id uuid,
 target_client_reference text,target_sale_date timestamptz,target_discount numeric,target_tax numeric,
 target_amount_paid numeric,target_payment_method text,target_notes text,target_device_id uuid,target_items jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'customer_id',target_customer_id,'client_reference',target_client_reference,'sale_date',target_sale_date,'discount',target_discount,'tax',target_tax,'amount_paid',target_amount_paid,'payment_method',target_payment_method,'notes',target_notes,'device_id',target_device_id,'items',target_items)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_client_reference,'sale.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_client_reference for update;
 if idem.operation_type<>'sale.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.create_sale_atomic(target_business_id,target_location_id,target_customer_id,target_client_reference,target_sale_date,target_discount,target_tax,target_amount_paid,target_payment_method,target_notes,target_device_id,target_items);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_create_return_atomic(
 target_user_id uuid,target_business_id uuid,target_sale_id uuid,target_client_reference text,target_reason text,
 target_refund_amount numeric,target_device_id uuid,target_items jsonb)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('sale_id',target_sale_id,'client_reference',target_client_reference,'reason',target_reason,'refund_amount',target_refund_amount,'device_id',target_device_id,'items',target_items)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_client_reference,'return.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_client_reference for update;
 if idem.operation_type<>'return.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.create_return_atomic(target_business_id,target_sale_id,target_client_reference,target_reason,target_refund_amount,target_device_id,target_items);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_record_customer_repayment(
 target_user_id uuid,target_business_id uuid,target_customer_id uuid,target_amount numeric,target_operation_id text,
 target_payment_method text,target_note text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('customer_id',target_customer_id,'amount',target_amount,'payment_method',target_payment_method,'note',target_note,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'customer.repayment',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'customer.repayment' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_customer_repayment(target_business_id,target_customer_id,target_amount,target_operation_id,target_payment_method,target_note,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_record_expense(
 target_user_id uuid,target_business_id uuid,target_location_id uuid,target_amount numeric,target_category text,
 target_description text,target_operation_id text,target_device_id uuid,target_payment_method text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'amount',target_amount,'category',target_category,'description',target_description,'device_id',target_device_id,'payment_method',target_payment_method)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'expense.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'expense.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_expense(target_business_id,target_location_id,target_amount,target_category,target_description,target_operation_id,target_device_id,target_payment_method);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_record_sale_payment(
 target_user_id uuid,target_business_id uuid,target_sale_id uuid,target_amount numeric,target_operation_id text,
 target_payment_method text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('sale_id',target_sale_id,'amount',target_amount,'payment_method',target_payment_method,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'sale.payment',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'sale.payment' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_sale_payment(target_business_id,target_sale_id,target_amount,target_operation_id,target_payment_method,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_cloud_open_cash_drawer_shift(
 target_user_id uuid,target_business_id uuid,target_location_id uuid,target_opening_cash numeric,target_opened_at timestamptz,
 target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'opening_cash',target_opening_cash,'opened_at',target_opened_at,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'cash_drawer_shift.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'cash_drawer_shift.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.cloud_open_cash_drawer_shift(target_business_id,target_location_id,target_opening_cash,target_opened_at,target_operation_id,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(
 target_user_id uuid,target_business_id uuid,target_shift_id uuid,target_closing_cash numeric,target_cash_difference numeric,
 target_closing_note text,target_closed_at timestamptz,target_operation_id text,target_device_id uuid,target_base_cursor bigint)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('shift_id',target_shift_id,'closing_cash',target_closing_cash,'cash_difference',target_cash_difference,'closing_note',target_closing_note,'closed_at',target_closed_at,'device_id',target_device_id,'base_cursor',target_base_cursor)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'cash_drawer_shift.close',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'cash_drawer_shift.close' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.cloud_close_cash_drawer_shift(target_business_id,target_shift_id,target_closing_cash,target_cash_difference,target_closing_note,target_closed_at,target_operation_id,target_device_id,target_base_cursor);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_cloud_record_income(
 target_user_id uuid,target_business_id uuid,target_location_id uuid,target_source text,target_amount numeric,target_income_date timestamptz,
 target_notes text,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'source',target_source,'amount',target_amount,'income_date',target_income_date,'notes',target_notes,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'income.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'income.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.cloud_record_income(target_business_id,target_location_id,target_source,target_amount,target_income_date,target_notes,target_operation_id,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_create_location(
 target_user_id uuid,target_business_id uuid,target_operation_id text,target_name text,target_code text,target_address text,target_timezone text)
returns jsonb language plpgsql security definer set search_path to ''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 request_hash:=md5(jsonb_build_object('name',target_name,'code',target_code,'address',target_address,'timezone',target_timezone)::text);
 insert into public.idempotency_keys(business_id,user_id,key,operation_type,request_hash) values(target_business_id,target_user_id,target_operation_id,'location.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.operation_type<>'location.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.create_location(target_business_id,target_operation_id,target_name,target_code,target_address,target_timezone);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

revoke execute on function public.fulus_api_create_sale_atomic(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb) from anon,authenticated;
revoke execute on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb) from anon,authenticated;
revoke execute on function public.fulus_api_record_customer_repayment(uuid,uuid,uuid,numeric,text,text,text,uuid) from anon,authenticated;
revoke execute on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid,text) from anon,authenticated;
revoke execute on function public.fulus_api_record_sale_payment(uuid,uuid,uuid,numeric,text,text,uuid) from anon,authenticated;
revoke execute on function public.fulus_api_cloud_open_cash_drawer_shift(uuid,uuid,uuid,numeric,timestamptz,text,uuid) from anon,authenticated;
revoke execute on function public.fulus_api_cloud_close_cash_drawer_shift(uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint) from anon,authenticated;
revoke execute on function public.fulus_api_cloud_record_income(uuid,uuid,uuid,text,numeric,timestamptz,text,text,uuid) from anon,authenticated;
revoke execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from anon,authenticated;
grant execute on function public.fulus_api_create_sale_atomic(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb) to service_role;
grant execute on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb) to service_role;
grant execute on function public.fulus_api_record_customer_repayment(uuid,uuid,uuid,numeric,text,text,text,uuid) to service_role;
grant execute on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid,text) to service_role;
grant execute on function public.fulus_api_record_sale_payment(uuid,uuid,uuid,numeric,text,text,uuid) to service_role;
grant execute on function public.fulus_api_cloud_open_cash_drawer_shift(uuid,uuid,uuid,numeric,timestamptz,text,uuid) to service_role;
grant execute on function public.fulus_api_cloud_close_cash_drawer_shift(uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid,bigint) to service_role;
grant execute on function public.fulus_api_cloud_record_income(uuid,uuid,uuid,text,numeric,timestamptz,text,text,uuid) to service_role;
grant execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) to service_role;
