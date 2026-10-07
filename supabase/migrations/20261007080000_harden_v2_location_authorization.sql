-- Harden the V2 financial command boundary without rewriting the existing
-- implementation bodies in-place. The historical migrations define the
-- transaction implementations; this migration renames those implementations
-- to private service-role helpers and places the location authorization
-- boundary in the stable public V2 entrypoints.
--
-- The wrapper sets the authoritative actor claim before authorization. The
-- Edge Function uses service_role for the database call, so authorization
-- must never depend on the service-role identity.

alter function public.fulus_api_create_sale_atomic_v2(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb
) rename to fulus_api_create_sale_atomic_v2_unchecked;

alter function public.fulus_api_create_return_atomic_v2(
  uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb
) rename to fulus_api_create_return_atomic_v2_unchecked;

create or replace function public.fulus_api_create_sale_atomic_v2(
  target_user_id uuid,
  target_business_id uuid,
  target_location_id uuid,
  target_customer_id uuid,
  target_client_reference text,
  target_sale_date timestamptz,
  target_discount numeric,
  target_tax numeric,
  target_amount_paid numeric,
  target_payment_method text,
  target_notes text,
  target_device_id uuid,
  target_items jsonb,
  target_payments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  perform public.require_location_access(target_business_id,target_location_id);

  return public.fulus_api_create_sale_atomic_v2_unchecked(
    target_user_id,
    target_business_id,
    target_location_id,
    target_customer_id,
    target_client_reference,
    target_sale_date,
    target_discount,
    target_tax,
    target_amount_paid,
    target_payment_method,
    target_notes,
    target_device_id,
    target_items,
    target_payments
  );
end;
$function$;

create or replace function public.fulus_api_create_return_atomic_v2(
  target_user_id uuid,
  target_business_id uuid,
  target_sale_id uuid,
  target_client_reference text,
  target_reason text,
  target_refund_amount numeric,
  target_refund_method text,
  target_device_id uuid,
  target_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  perform public.require_sale_location_access(target_business_id,target_sale_id);

  return public.fulus_api_create_return_atomic_v2_unchecked(
    target_user_id,
    target_business_id,
    target_sale_id,
    target_client_reference,
    target_reason,
    target_refund_amount,
    target_refund_method,
    target_device_id,
    target_items
  );
end;
$function$;

revoke all on function public.fulus_api_create_sale_atomic_v2_unchecked(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_return_atomic_v2_unchecked(
  uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_sale_atomic_v2(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb
) from public,anon,authenticated;

revoke all on function public.fulus_api_create_return_atomic_v2(
  uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb
) from public,anon,authenticated;

grant execute on function public.fulus_api_create_sale_atomic_v2(
  uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb,jsonb
) to service_role;

grant execute on function public.fulus_api_create_return_atomic_v2(
  uuid,uuid,uuid,text,text,numeric,text,uuid,jsonb
) to service_role;
