-- Cover foreign-key lookups identified by the live Supabase performance advisor.
-- These indexes are additive and do not alter row visibility or application behavior.
create index if not exists customers_location_id_idx
  on public.customers (location_id);

create index if not exists products_location_id_idx
  on public.products (location_id);

create index if not exists location_ownership_review_reviewed_by_idx
  on public.location_ownership_review (reviewed_by);
