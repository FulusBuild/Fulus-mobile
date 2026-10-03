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
**Status:** Open; runtime evidence gap.

**Observed limitation**

The live multi-device suite exercises catalog OCC, inventory concurrency, idempotency, and bidirectional feed delivery, but it does not execute a complete adversarial financial scenario across two devices such as concurrent offline sales/returns/customer repayments followed by reconnect, canonical reconciliation, and final local convergence.

**Expected invariant**

Financial, inventory, customer-credit, and authorization invariants must converge correctly after concurrent device operations, not only catalog edits.

**Impact**

The existing source and live tests establish strong coverage of the generic conflict/feed mechanism, but they do not provide direct production evidence for every high-impact financial multi-device interaction.

**Fix / verification**

Do not change the sync architecture speculatively. Add a production-safe multi-device runtime scenario covering at least:
- concurrent sale creation;
- sale/return interaction;
- customer repayment/credit interaction;
- reconnect after offline work;
- canonical pull on both devices;
- final balance/stock/ledger equality;
- duplicate retry behavior.

This is a verification gap rather than a demonstrated source defect.

## Cross-check

The generic conflict model, canonical reconcilers, queue fencing, idempotency, and stale-cursor recovery were checked for the same failure class. No additional concrete source defect was proven in this pass.

## Remaining evidence

- P16-001 requires adversarial financial multi-device runtime evidence.
- Android process-death remains P17-001.
- Security/tenant isolation is completed in Part 20.
