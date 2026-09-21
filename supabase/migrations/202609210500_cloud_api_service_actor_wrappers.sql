-- Cloud API service boundary for auth.uid()-based business RPCs.
--
-- The Edge Function authenticates the caller once, then calls these
-- service-role-only wrappers with the validated caller user id. Each wrapper
-- installs that user id as the transaction-local JWT subject before delegating
-- to the existing business function, so auth.uid() remains the real caller.
--
-- This preserves the existing RPC execute lockdown instead of granting direct
-- mutation RPC access to authenticated clients.

create or replace function public.fulus_api_register_device(
  target_user_id uuid, target_business_id uuid, target_device_client_id text,
  target_device_name text, target_platform text, target_app_version text
)
returns public.devices language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.register_device(target_business_id, target_user_id, target_device_client_id,
    target_device_name, target_platform, target_app_version);
end;
$$;

create or replace function public.fulus_api_create_location(
  target_user_id uuid, target_business_id uuid, target_operation_id text,
  target_name text, target_code text, target_address text, target_timezone text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_location(target_business_id, target_operation_id, target_name,
    target_code, target_address, target_timezone);
end;
$$;

create or replace function public.fulus_api_create_customer(
  target_user_id uuid, target_business_id uuid, target_name text, target_phone text,
  target_email text, target_address text, target_credit_limit numeric
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_customer(target_business_id, target_name, target_phone,
    target_email, target_address, target_credit_limit);
end;
$$;

create or replace function public.fulus_api_record_sale_payment(
  target_user_id uuid, target_business_id uuid, target_sale_id uuid, target_amount numeric,
  target_operation_id text, target_payment_method text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.record_sale_payment(target_business_id, target_sale_id, target_amount,
    target_operation_id, target_payment_method, target_device_id);
end;
$$;

create or replace function public.fulus_api_create_sale_atomic(
  target_user_id uuid, target_business_id uuid, target_location_id uuid, target_customer_id uuid,
  target_client_reference text, target_sale_date timestamptz, target_discount numeric,
  target_tax numeric, target_amount_paid numeric, target_payment_method text, target_notes text,
  target_device_id uuid, target_items jsonb
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_sale_atomic(target_business_id, target_location_id, target_customer_id,
    target_client_reference, target_sale_date, target_discount, target_tax, target_amount_paid,
    target_payment_method, target_notes, target_device_id, target_items);
end;
$$;

create or replace function public.fulus_api_record_customer_repayment(
  target_user_id uuid, target_business_id uuid, target_customer_id uuid, target_amount numeric,
  target_operation_id text, target_payment_method text, target_note text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.record_customer_repayment(target_business_id, target_customer_id, target_amount,
    target_operation_id, target_payment_method, target_note, target_device_id);
end;
$$;

create or replace function public.fulus_api_record_expense(
  target_user_id uuid, target_business_id uuid, target_location_id uuid, target_amount numeric,
  target_category text, target_description text, target_operation_id text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.record_expense(target_business_id, target_location_id, target_amount,
    target_category, target_description, target_operation_id, target_device_id);
end;
$$;

create or replace function public.fulus_api_create_return_atomic(
  target_user_id uuid, target_business_id uuid, target_sale_id uuid, target_client_reference text,
  target_reason text, target_refund_amount numeric, target_device_id uuid, target_items jsonb
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.create_return_atomic(target_business_id, target_sale_id, target_client_reference,
    target_reason, target_refund_amount, target_device_id, target_items);
end;
$$;

create or replace function public.fulus_api_apply_inventory_adjustment(
  target_user_id uuid, target_business_id uuid, target_product_id uuid, target_location_id uuid,
  target_quantity_delta integer, target_reason text, target_operation_id text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.apply_inventory_adjustment(target_business_id, target_product_id, target_location_id,
    target_quantity_delta, target_reason, target_operation_id, target_device_id);
end;
$$;

create or replace function public.fulus_api_cloud_record_income(
  target_user_id uuid, target_business_id uuid, target_location_id uuid, target_source text,
  target_amount numeric, target_income_date timestamptz, target_notes text,
  target_operation_id text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.cloud_record_income(target_business_id, target_location_id, target_source,
    target_amount, target_income_date, target_notes, target_operation_id, target_device_id);
end;
$$;

create or replace function public.fulus_api_cloud_open_cash_drawer_shift(
  target_user_id uuid, target_business_id uuid, target_location_id uuid, target_opening_cash numeric,
  target_opened_at timestamptz, target_operation_id text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.cloud_open_cash_drawer_shift(target_business_id, target_location_id,
    target_opening_cash, target_opened_at, target_operation_id, target_device_id);
end;
$$;

create or replace function public.fulus_api_cloud_close_cash_drawer_shift(
  target_user_id uuid, target_business_id uuid, target_shift_id uuid, target_closing_cash numeric,
  target_cash_difference numeric, target_closing_note text, target_closed_at timestamptz,
  target_operation_id text, target_device_id uuid
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform set_config('request.jwt.claim.sub', target_user_id::text, true);
  return public.cloud_close_cash_drawer_shift(target_business_id, target_shift_id, target_closing_cash,
    target_cash_difference, target_closing_note, target_closed_at, target_operation_id, target_device_id);
end;
$$;

revoke all on function public.fulus_api_register_device(uuid,uuid,text,text,text,text) from public, anon, authenticated;
revoke all on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.fulus_api_create_customer(uuid,uuid,text,text,text,text,numeric) from public, anon, authenticated;
revoke all on function public.fulus_api_record_sale_payment(uuid,uuid,uuid,numeric,text,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_create_sale_atomic(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.fulus_api_record_customer_repayment(uuid,uuid,uuid,numeric,text,text,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.fulus_api_apply_inventory_adjustment(uuid,uuid,uuid,uuid,integer,text,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_cloud_record_income(uuid,uuid,uuid,text,numeric,timestamptz,text,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_cloud_open_cash_drawer_shift(uuid,uuid,uuid,numeric,timestamptz,text,uuid) from public, anon, authenticated;
revoke all on function public.fulus_api_cloud_close_cash_drawer_shift(uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid) from public, anon, authenticated;

grant execute on function public.fulus_api_register_device(uuid,uuid,text,text,text,text) to service_role;
grant execute on function public.fulus_api_create_location(uuid,uuid,text,text,text,text,text) to service_role;
grant execute on function public.fulus_api_create_customer(uuid,uuid,text,text,text,text,numeric) to service_role;
grant execute on function public.fulus_api_record_sale_payment(uuid,uuid,uuid,numeric,text,text,uuid) to service_role;
grant execute on function public.fulus_api_create_sale_atomic(uuid,uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb) to service_role;
grant execute on function public.fulus_api_record_customer_repayment(uuid,uuid,uuid,numeric,text,text,text,uuid) to service_role;
grant execute on function public.fulus_api_record_expense(uuid,uuid,uuid,numeric,text,text,text,uuid) to service_role;
grant execute on function public.fulus_api_create_return_atomic(uuid,uuid,uuid,text,text,numeric,uuid,jsonb) to service_role;
grant execute on function public.fulus_api_apply_inventory_adjustment(uuid,uuid,uuid,uuid,integer,text,text,uuid) to service_role;
grant execute on function public.fulus_api_cloud_record_income(uuid,uuid,uuid,text,numeric,timestamptz,text,text,uuid) to service_role;
grant execute on function public.fulus_api_cloud_open_cash_drawer_shift(uuid,uuid,uuid,numeric,timestamptz,text,uuid) to service_role;
grant execute on function public.fulus_api_cloud_close_cash_drawer_shift(uuid,uuid,uuid,numeric,numeric,text,timestamptz,text,uuid) to service_role;
