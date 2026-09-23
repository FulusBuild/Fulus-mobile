-- These lower-level SECURITY DEFINER mutations are implementation helpers.
-- The public/service API must enter through the fulus_api_* wrappers, which bind
-- the requested user and device and perform request idempotency checks.
revoke execute on function public.apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.cloud_open_cash_drawer_shift(uuid,uuid,numeric,timestamptz,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.cloud_record_income(uuid,uuid,text,numeric,timestamptz,text,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.record_customer_repayment(uuid,uuid,numeric,text,text,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.record_sale_payment(uuid,uuid,numeric,text,text,uuid) from service_role, public, anon, authenticated;
revoke execute on function public.record_expense(uuid,uuid,numeric,text,text,text,uuid,text) from service_role, public, anon, authenticated;
revoke execute on function public.record_expense(uuid,uuid,numeric,text,text,text,uuid) from service_role, public, anon, authenticated;
