-- Sale amounts and payment legs use exact two-decimal currency values.
-- The previous implementation tolerated a one-cent mismatch, which could
-- allow cash_ledger to record more than sales.amount_paid after the base
-- sale RPC capped the latter at the sale total.
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
declare
  result jsonb;
  payment jsonb;
  method text;
  payment_amount numeric;
  payment_total numeric := 0;
  collected_total numeric := 0;
  credit_total numeric := 0;
begin
  perform set_config('request.jwt.claim.sub',target_user_id::text,true);
  perform public.require_location_access(target_business_id,target_location_id);

  result := public.fulus_api_create_sale_atomic_v2_unchecked(
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

  if coalesce(result->>'status','') = 'applied' then
    for payment in select * from jsonb_array_elements(target_payments) loop
      method := lower(trim(payment->>'method'));
      payment_amount := round((payment->>'amount')::numeric,2);
      payment_total := payment_total + payment_amount;
      if method = 'credit' then
        credit_total := credit_total + payment_amount;
      else
        collected_total := collected_total + payment_amount;
      end if;
    end loop;

    if round(payment_total,2) <> round((result->>'total')::numeric,2) then
      raise exception using errcode='22023',message='Sale payment legs must exactly equal the server-calculated total';
    end if;
    if round(collected_total,2) <> round((result->>'amount_paid')::numeric,2) then
      raise exception using errcode='22023',message='Collected payment legs must exactly equal the server amount paid';
    end if;
    if round(credit_total,2) <> round((result->>'balance_due')::numeric,2) then
      raise exception using errcode='22023',message='Credit payment legs must exactly equal the server balance due';
    end if;
    if round(target_amount_paid,2) <> round(collected_total,2) then
      raise exception using errcode='22023',message='Requested amount paid must exactly equal collected payment legs';
    end if;
  end if;

  return result;
end;
$function$;

