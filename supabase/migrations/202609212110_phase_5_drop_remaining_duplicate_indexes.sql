-- Remove duplicate indexes identified by the production performance advisor.
-- Keep the canonical FK indexes introduced by the sync hardening migrations.
drop index if exists public.idx_sale_items_product;
drop index if exists public.idx_sale_items_sale;
drop index if exists public.return_items_return_idx;
