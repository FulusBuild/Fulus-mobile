-- Remove indexes proven identical by the production performance advisor.
-- Keep the canonical named indexes already used by the schema.
DROP INDEX IF EXISTS public.idx_cash_ledger_business_created;
DROP INDEX IF EXISTS public.idx_customer_ledger_business_created;
DROP INDEX IF EXISTS public.idx_expenses_business_date;
DROP INDEX IF EXISTS public.sale_items_sale_idx;
