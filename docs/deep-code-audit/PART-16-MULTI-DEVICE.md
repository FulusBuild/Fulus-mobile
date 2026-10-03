# Part 16 — Multi-Device Convergence & Conflict Safety

**Status:** In progress  
**Baseline:** `main` after Part 15 merge `39ea55dd1406f2bde14d202e7edca7d728c35aef`

## Pass A — Structural inventory

Inspected the multi-device boundary across:

- `lib/sync/sync_engine.dart`
- `lib/sync/sync_conflict_resolver.dart`
- `lib/sync/sync_queue.dart`
- `lib/data/remote/cloud_sync_recovery.dart`
- typed canonical reconcilers for product, sale, customer, employee, return, expense, income, supplier, category, and cash drawer
- sync handlers carrying `baseCursor`
- `supabase/functions/fulus-api/index.ts`
- optimistic-concurrency and idempotency migrations
- `tool/fulus_sync_e2e.dart`
- `tool/fulus_multi_device_e2e.dart`
- conflict/queue/canonical reconciliation tests

## Pass B — Conflict and convergence model

### Server-side OCC

Catalog mutations carry a base cursor. The authoritative catalog transaction serializes concurrent edits and rejects a stale cursor with `P0008 / SYNC_CONFLICT`.

The live E2E suite proves both:
- a stale catalog update is rejected with HTTP 409 / `SYNC_CONFLICT`;
- two concurrent catalog edits from the same observed cursor produce exactly one success and one conflict.

The server also protects idempotency by operation identity and request hash. Reusing an operation with different data is rejected rather than silently treated as a duplicate.

### Durable local conflict state

A conflict is represented by a durable `sync_conflict_records` row keyed from the queue operation. Repeated conflict observation is idempotent.

The queue remains parked for attention instead of being deleted on conflict. This preserves the local mutation for explicit resolution.

### Keep-cloud resolution

`SyncConflictResolver.keepCloudVersion`:
1. re-reads the unresolved conflict after acquiring the cross-runtime SQLite lease;
2. resolves the local record to its server identity;
3. fetches canonical cloud state;
4. verifies the canonical entity type/id;
5. applies canonical state inside the lease-protected transaction;
6. deletes the conflicted queue row;
7. marks the conflict resolved.

### Keep-local resolution

`keepLocalVersion`:
1. re-reads the unresolved conflict under the lease;
2. requires the original queue row to still exist;
3. fetches the current canonical entity;
4. obtains the latest authoritative sequence;
5. rebases the queued mutation's base cursor;
6. clears retry state so the mutation can be retried.

The conflict remains unresolved until the cloud accepts the rebased mutation.

### Canonical pull fencing

Canonical pull applies entity-specific reconciliation while the sync execution lease is held. Part 14 already closed the employee pending-mutation fencing omission. The multi-device audit cross-checked the same protection across the other typed canonical reconcilers.

## Pass C — Identity, retries and failure paths

### Device identity

The server receives an explicit device client identity and the production E2E registers a second device before exercising the feed in both directions. Device revocation and authorization are handled separately from business-row identity.

### Durable retries

Queue rows, operation IDs, base cursors, conflict records and retry state survive runtime restart. Authentication/device authorization failures do not permanently delete queued work.

### Cursor-too-old recovery

`CloudSyncRecovery` blocks snapshot replacement while outbound work or unresolved conflicts remain. This prevents stale-cursor recovery from silently replacing legitimate local edits.

## Pass D — End-to-end evidence

The current live suites prove:

- device A mutation is visible from device B;
- device B mutation is visible from device A;
- stale catalog OCC is rejected;
- concurrent catalog edits serialize to one success + one conflict;
- concurrent absolute inventory updates serialize at the server;
- idempotent inventory replay succeeds;
- conflicting inventory replay is rejected;
- production sync API/device registration paths are exercised.

### P16-001

**Severity:** Medium  
**Status:** Closed in source and production; runtime regression coverage added.

**Finding**

The adversarial financial scenario exposed two concrete return-path defects in addition to the original evidence gap:

1. Credit-method returns could apply the same customer credit reversal twice because the validation branch performed the ledger/customer mutation and the common credit settlement branch performed it again.
2. A later return-function replacement dropped the verified target_user_id → auth.uid() binding before has_permission(). The service-role Edge Function therefore evaluated return permission in the wrong actor context.

**Fix**

- Added 20261003120000_fix_credit_return_single_reversal.sql to make the credit calculation branch side-effect free.
- Added 20261003130000_fix_return_actor_binding.sql to restore end-user actor binding before permission evaluation.
- Applied both corrective migrations to the production Supabase project.
- Added live multi-device E2E coverage for concurrent sale + repayment, duplicate retries, credit return, return replay, canonical feed visibility, and final customer/sale invariants.
- Added a two-independent-SQLite regression proving the same canonical financial sale converges into separate local stores.
- Existing supabase/tests/financial_fidelity.sql directly rejects a credit validation branch that performs a customer-ledger insert.

**Production verification**

The production function definition was re-read after migration and verified to contain the verified actor binding before has_permission(), and no customer-ledger insert in the credit validation branch.

**Remaining execution**

The repository live E2E is wired into CI, but this connector cannot dispatch the pull-request workflow directly. The code/runtime scenario is prepared and the production function has been verified; the final CI execution result must still be observed before claiming the workflow itself green.
## Cross-check

The generic conflict model, canonical reconcilers, queue fencing, idempotency, and stale-cursor recovery were checked for the same failure class. No additional concrete source defect was proven in this pass.

## Remaining evidence

- P16-001 now has live API-level evidence for concurrent sale/repayment, duplicate retry, feed delivery, and final server invariants.
- P16-001 remains open for actual two-runtime local SQLite convergence and an authorized live sale/return interaction.
- Android process-death remains P17-001.
- Security/tenant isolation is completed in Part 20.
