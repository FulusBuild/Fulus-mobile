-- Scale hardening: make the 90-day sync-change retention sweep index-backed.
-- The retention job orders by created_at, sequence while deleting in small
-- batches. Without this index, a large global change feed would require an
-- increasingly expensive scan as the number of businesses/devices grows.
create index if not exists sync_changes_created_at_sequence_idx
on public.sync_changes (created_at, sequence);
