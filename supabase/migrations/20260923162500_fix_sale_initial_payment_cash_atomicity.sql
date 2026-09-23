-- Paid-at-sale amounts must have the same durable payment/cash representation
-- as subsequent sale payments. Keep this inside the sale action transaction.

create or replace function public.fulus_api_create_sale_atomic(target_user_id uuid,target_business_id uuid,target_location_id uuid,target_customer_id uuid,target_client_reference text,target_sale_date timestamptz,target_discount numeric,target_tax numeric,target_amount_paid numeric,target_payment_method text,target_notes text,target_device_id uuid,target_items jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare idem public.idempotency_keys%rowtype; request_hash text; result jsonb; sale_id uuid; payment_id uuid; actual_paid numeric;
begin
 if not exists(select 1 from public.devices where id=target_device_id and business_id=target_business_id and registered_by=target_user_id and status='active') then raise exception using errcode='42501',message='Device is not registered or active'; end if;
 request_hash:=md5(jsonb_build_object('location_id',target_location_id,'customer_id',target_customer_id,'client_reference',target_client_reference,'sale_date',target_sale_date,'discount',target_discount,'tax',target_tax,'amount_paid',target_amount_paid,'payment_method',target_payment_method,'notes',target_notes,'device_id',target_device_id,'items',target_items)::text);
 insert into public.idempotency_keys(business_id,device_id,user_id,key,operation_type,request_hash) values(target_business_id,target_device_id,target_user_id,target_client_reference,'sale.create',request_hash) on conflict(business_id,key) do nothing;
 select * into idem from public.idempotency_keys where business_id=target_business_id and key=target_client_reference for update;
 if idem.operation_type<>'sale.create' or idem.request_hash<>request_hash then raise exception using errcode='P0009',message='Operation id was already used with a different request'; end if;
 if idem.completed_at is not null and idem.response_body is not null then return idem.response_body; end if;
 perform set_config('request.jwt.claim.sub',target_user_id::text,true);
 result:=public.create_sale_atomic(target_business_id,target_location_id,target_customer_id,target_client_reference,target_sale_date,target_discount,target_tax,target_amount_paid,target_payment_method,target_notes,target_device_id,target_items);
 if coalesce((result->>'status'),'')='applied' and coalesce(target_amount_paid,0)>0 and target_payment_method is not null then
   sale_id:=(result->>'sale_id')::uuid;
   actual_paid:=coalesce(target_amount_paid,0);
   insert into public.sale_payments(business_id,sale_id,amount,payment_method,operation_id,created_by,device_id)
   values(target_business_id,sale_id,actual_paid,target_payment_method,target_client_reference||':initial-payment',target_user_id,target_device_id)
   on conflict(business_id,operation_id) do nothing
   returning id into payment_id;
   if payment_id is not null then
     insert into public.cash_ledger(business_id,location_id,entry_type,amount,direction,reference_id,operation_id,created_by,device_id)
     values(target_business_id,target_location_id,'sale',actual_paid,'in',sale_id,target_client_reference||':initial-cash',target_user_id,target_device_id)
     on conflict(business_id,operation_id) do nothing;
   end if;
 end if;
 update public.idempotency_keys set response_status=200,response_body=result,completed_at=now() where id=idem.id;
 return result;
end;$function$;
