-- Match the local product repository and SQLite constraint: a nonblank
-- barcode identifies at most one active product within a business location.
-- Legacy products without an assigned location remain outside this constraint
-- until their ownership has been safely reconciled.
create unique index if not exists products_location_barcode_uq
  on public.products (business_id, location_id, barcode)
  where deleted_at is null
    and location_id is not null
    and barcode is not null
    and btrim(barcode) <> '';
