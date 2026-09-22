-- Phase 5 scale foundation: keep the durable sync feed and retry ledgers
-- indexed on their actual access paths. No retention/deletion policy is
-- introduced here; deleting old feed rows without a bootstrap snapshot would
-- make a client cursor unrecoverable.
create index if not exists idx_sync_changes_business_sequence
  on public.sync_changes (business_id, sequence);

create index if not exists idx_sync_changes_business_entity
  on public.sync_changes (business_id, entity_type, entity_id, sequence);

create index if not exists idx_sync_operations_business_created_at
  on public.sync_operations (business_id, received_at desc);

create index if not exists idx_idempotency_keys_business_created_at
  on public.idempotency_keys (business_id, created_at desc);

create index if not exists idx_idempotency_keys_business_operation
  on public.idempotency_keys (business_id, operation_type, key);
