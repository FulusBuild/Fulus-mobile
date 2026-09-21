-- Keep the pre-existing production sync feed indexes; the phase-5
-- migration was deliberately conservative, but the production advisor shows
-- equivalent indexes already existed. Remove only the redundant copies.
drop index if exists public.idx_sync_changes_business_sequence;
drop index if exists public.idx_sync_changes_business_entity;