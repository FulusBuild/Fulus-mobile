create index if not exists idx_sales_business_date on public.sales(business_id,sale_date desc) where deleted_at is null;
create index if not exists idx_sale_items_sale on public.sale_items(sale_id);
create index if not exists idx_sale_items_product on public.sale_items(product_id);
create index if not exists idx_expenses_business_date on public.expenses(business_id,expense_date desc) where deleted_at is null;
create index if not exists idx_customers_business_balance on public.customers(business_id,outstanding_balance desc) where is_active=true;
create index if not exists idx_stock_levels_location_product on public.product_stock_levels(location_id,product_id);
create index if not exists idx_cash_ledger_business_created on public.cash_ledger(business_id,created_at desc);
create index if not exists idx_customer_ledger_business_created on public.customer_ledger_entries(business_id,created_at desc);