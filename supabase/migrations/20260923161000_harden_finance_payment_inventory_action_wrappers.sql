-- Harden public action wrappers with active user-owned device scope and a
-- consistent idempotency boundary. Keep the legacy 8-argument expense wrapper
-- as a compatibility shim into the hardened 9-argument implementation.

create or replace function public.fulus_api_record_sale_payment(target_user_id uuid,target_business_id uuid,target_sale_id uuid,target_amount numeric,target_operation_id text,target_payment_method text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 request_hash:=md5(jsonb_build_object('sale_id',target_sale_id,'amount',target_amount,'payment_method',target_payment_method,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'sale.payment',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
 if idem.operation_type<>'sale.payment' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_sale_payment(target_business_id,target_sale_id,target_amount,target_operation_id,target_payment_method,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_record_customer_repayment(target_user_id uuid,target_business_id uuid,target_customer_id uuid,target_amount numeric,target_operation_id text,target_payment_method text,target_note text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 request_hash:=md5(jsonb_build_object('customer_id',target_customer_id,'amount',target_amount,'payment_method',target_payment_method,'note',target_note,'device_id',target_device_id)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'customer.repayment',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
 if idem.operation_type<>'customer.repayment' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_customer_repayment(target_business_id,target_customer_id,target_amount,target_operation_id,target_payment_method,target_note,target_device_id);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_record_expense(target_user_id uuid,target_business_id uuid,target_location_id uuid,target_amount numeric,target_category text,target_description text,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
 return public.fulus_api_record_expense(target_user_id,target_business_id,target_location_id,target_amount,target_category,target_description,target_operation_id,target_device_id,null::text);
end;$function$;

create or replace function public.fulus_api_record_expense(target_user_id uuid,target_business_id uuid,target_location_id uuid,target_amount numeric,target_category text,target_description text,target_operation_id text,target_device_id uuid,target_payment_method text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb;
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'amount',target_amount,'category',target_category,'description',target_description,'device_id',target_device_id,'payment_method',target_payment_method)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_operation_id,'expense.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_operation_id for update;
 if idem.device_id is distinct from target_device_id or idem.user_id is distinct from target_user_id then raise exception using errcode='P0009',message='Operation id was already used from a different device or account'; end if;
 if idem.operation_type<>'expense.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.record_expense(target_business_id,target_location_id,target_amount,target_category,target_description,target_operation_id,target_device_id,target_payment_method);
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;

create or replace function public.fulus_api_apply_inventory_adjustment(target_user_id uuid,target_business_id uuid,target_product_id uuid,target_location_id uuid,target_quantity_delta integer,target_reason text,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 return public.apply_inventory_adjustment(target_business_id,target_product_id,target_location_id,target_quantity_delta,target_reason,target_operation_id,target_device_id);
end;$function$;

create or replace function public.fulus_api_set_inventory_quantity(target_user_id uuid,target_business_id uuid,target_product_id uuid,target_location_id uuid,target_new_quantity integer,target_reason text,target_operation_id text,target_device_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 return public.set_inventory_quantity(target_business_id,target_product_id,target_location_id,target_new_quantity,target_reason,target_operation_id,target_device_id);
end;$function$;
