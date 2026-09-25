# Fulus Mobile — Cloud Sync V1 Audit Continuation

Continue the exhaustive Cloud Sync V1 production-readiness audit for `FulusBuild/Fulus-mobile`, branch `main`.

Do not restart the audit. Do not merely write a report. Work iteratively:

**inspect → prove → fix → regression/E2E test → commit → CI → inspect CI → continue.**

Do not stop at the first green CI run. Do not build an APK unless explicitly requested.

## Immediate starting point

Latest fix commit:

`837255d6a25f1fae694bf52c133d15edd5373e60`

The mutation-matrix E2E previously failed at `expense.update` because production `expenses` has no `updated_at` column. Verified production columns are:

`id, business_id, location_id, amount, category, description, operation_id, expense_date, created_by, device_id, payment_method`.

The bad `updated_at=now()` assignment was removed from:

`supabase/migrations/202609211800_phase_3_optimistic_concurrency.sql`

**First task:** find the latest CI run for the fix commit, monitor it to completion, fix every failure, and verify the corrected `fulus_api_update_expense` function is actually deployed in Supabase. Never assume repository HEAD equals production.

## Already hardened areas

Do not redo these blindly, but verify current implementation where relevant:

- local-first SQLite → durable outbox → API → authoritative Supabase mutation → `sync_changes` → cursor → canonical reconciliation
- product initial stock/location atomic creation
- sync readiness/reconnect and cursor-too-old recovery
- native/web backup separation
- Quick Sale cloud sync
- income contract normalization
- stock sale/return change-feed emission and timestamps
- restore FK ordering and queue/conflict clearing
- expense categories
- action idempotency and concurrency locks
- SyncQueue race hardening
- recovery failure propagation
- retry semantics
- user-facing sync error sanitization
- rejected sale/return/customer-repayment reconciliation
- financial rejection handling
- location idempotency/replay
- live mutation matrix
- cumulative return quantity enforcement
- active-device scope hardening
- finance/payment/inventory RPC hardening
- cash drawer atomicity
- canonical aggregate sync model
- paid-at-creation sale/payment/cash atomicity
- cursor ordering/persistence hardening
- outbox process-death model test
- blocked/conflicted outbox supersession
- category/supplier lifecycle hardening
- authoritative restore and business-switching safety

Important commits include:

`0b3140da8d5af945912671b006b834353ddb5f34`
`b879d97d7bd7f232f095710ea0b1225ab6a7fbf3`
`7d1626f0ac957601319f7866f81efd19ad1eac19`
`dae22dca6fddc14a0a7208120667c7841396980e`
`821b15231e40636e041bd4ee778f5d83cec348e7`
`f5d15585834b3208aab3c5773b22aafbce924fbd`
`666adc776f6abc25fe15936f2de6eb52b9c4e580`
`ce9339c14b37f9b091458beb8daaa7fe6bfeb1ce`
`55cab545abda7ea4cafeca45eaf2b440537b3699`
`0d86dfce2916715bb461ff21703363a930c6cc56`
`5c139c4df17c337c7a64da946ce22ccf0059cd96`
`a3abb5b3933085a9cb648a00433cf8c6e3ea2846`
`8aac2446997786e65f96a2dbee27e4150df15aa3`
`837255d6a25f1fae694bf52c133d15edd5373e60`

## Remaining audit priorities

### 1. Full lifecycle audit

For every sync entity verify:

create, update, delete/archive, create→update before sync, create→delete before sync, repeated updates, blocked→newer mutation, conflict→newer mutation, replay, rejection, canonical reconciliation, and change-feed emission.

Entities:

`category, customer, customer_ledger, expense, expense_category, income_record, location, product, return, sale, stock_movement, supplier, cash_drawer_shift`.

### 2. Dependency ordering

Inspect actual:

- `lib/sync/sync_queue.dart`
- `lib/sync/sync_engine.dart`

Verify priority constants, dependency normalization, prerequisite server IDs, retry classification, starvation/deadlock, child-before-parent behavior, and create/update/delete coalescing.

Search all call sites of:

- `normalizeDependencyPriorities`
- `seedExistingBusinessData`

### 3. Process death

The current process-death test is modeled/unit-level. Determine whether true device-level kill/restart evidence is required.

Target proof:

local mutation → durable queue → server commit → process killed before queue deletion → restart → replay → idempotency prevents duplicate → queue converges.

### 4. Multi-device concurrency

Prove stale update rejection using base cursor, durable conflict creation, preservation of local state, safe canonical pull, and explicit resolution.

### 5. Offline/reconnect

Prove offline mutation persistence, app restart persistence, reconnect sync, exactly-once server effect, and replay safety when network dies after server commit.

### 6. Business switching

Prove A→B authoritative recovery, no cross-business mixing, correct cursor, post-recovery delta pull, Sync Ready only after success, and safe rollback if B recovery fails.

### 7. Security/RPC audit

For every mutation RPC inspect production:

- `pg_get_functiondef`
- `pg_get_function_identity_arguments`
- `proacl`

Verify no unsafe public execute, no dangerous legacy overload, SECURITY DEFINER, controlled `search_path`, membership/permission, active device scope, business scope, idempotency, request hash, operation type, and optimistic concurrency where required.

Search especially for `ON CONFLICT DO NOTHING` followed by an unlocked idempotency read.

### 8. Change-feed completeness

For every mutation verify authoritative mutation → exactly the correct `sync_changes` event.

Check entity type, entity ID, operation, payload, timestamps, business ID, sequence, and delete convergence.

### 9. Cursor/recovery adversarial tests

Test duplicate sequence, reordered sequence, global sequence gaps, empty page + `hasMore`, already-acknowledged page + `hasMore`, cursor ahead of response, cursor persistence failure, cursor-too-old recovery, post-recovery delta failure, and recovery process death.

### 10. Production integrity

Recheck negative stock, duplicate stock levels, impossible inventory movements, sale/payment mismatches, cash ledger mismatches, credit ledger mismatches, over-returns, orphaned sale items/payments/return items, invalid business/device relationships, stale devices, malformed sync changes, duplicate idempotency keys, unresolved conflicts, attention-needed records, and permanently stuck queue rows.

Do not delete production data merely to clean test artifacts.

### 11. Security observations

Previously observed:

- `diagnostic_events` has RLS but no policies; explicitly verify whether server-only access is intentional and secure.
- Supabase Auth leaked-password protection is disabled; classify as production security hardening.
- RLS performance advisories exist; do not blindly remove policies or indexes.

## Evidence standard

🟢 Proven = implementation + meaningful test/production evidence + CI.

🟡 Partial = implemented but missing an important proof layer.

🔴 Unknown = not verified or contradictory evidence.

Never say “probably safe.”

## Required engineering loop

For every defect:

inspect → reproduce/prove → establish authoritative contract → implement minimal durable fix → add regression/E2E coverage → commit → CI → inspect CI → production verification where possible → continue.

## Final objective

Make Cloud Sync V1 genuinely production-durable. Leave behind implementation, tests, CI evidence and production verification—not merely an audit report.


## 2026-09-25 concurrency continuation

### Proven and fixed in this continuation

- Durable local-business reset now requires successful acquisition of the shared SQLite sync lease. A failed acquisition no longer permits destructive reset. Regression coverage proves reset is refused while another runtime holds the lease.
- Cloud restore now uses the shared sync execution lease and starts its destructive import transaction with the lease ownership fence. Production wiring shares the same lease with the interactive restore path.
- Rejected-operation canonical recovery is fenced against a newer local mutation for the same entity. The check occurs inside the protected SQLite transaction after the canonical fetch, so an in-flight rejected operation cannot overwrite a newer queued local mutation.
- The guard covers product recovery from sale rejection, expense recovery, customer repayment recovery, return product/customer recovery, and cash-drawer recovery.
- Same-timestamp queued mutations are treated conservatively as newer for recovery fencing because queue timestamps are not a durable total-order identifier.
- Operation identity sweep confirms production client sync handlers pass the durable queue item ID as the server operation ID. Server migrations use business/device-scoped idempotency records and row locking for the audited command surface.
- CI verified green after the final concurrency changes: workflow run 36095959193 completed successfully, including static analysis, Flutter tests, live sync contract tests, and multi-device convergence tests.

### Final verification boundary

The concurrency audit's durable-state mutation sweep found no additional unprotected production path that can delete/overwrite sync queue state or cloud-owned business state outside the established lease/transaction boundaries. Ordinary local queue insertion remains intentionally lease-free because user mutations must be allowed to create newer durable work while a sync runtime is active; the stale-recovery fence explicitly preserves such newer work.

The established evidence standard remains: implementation plus regression/contract evidence plus green CI. No claim of exactly-once local execution is made; correctness relies on durable queue identity, server idempotency, canonical reconciliation, and at-least-once replay safety.


## 2026-09-25 queue-lifecycle continuation

### Section 1 audit progress

Inspected the durable queue implementation, sync engine, all production enqueue call sites, catalog/customer lifecycle handlers, and queue regression tests.

Verified:
- Local create + outbox insertion are performed in the same Drift transaction on audited repositories.
- Repeated updates replace the prior update queue identity instead of reusing it, protecting newer local mutations from stale queue completion.
- Create and update remain distinct queue operations so a create can establish the server identity before an update runs.
- Blocked/conflicted mutations can be superseded by a newer local mutation and the parked conflict is resolved.
- Concurrent enqueue of the same mutation is deduplicated transactionally.
- Pre-cloud seeding avoids already-server-backed rows and avoids duplicating an existing queued create.
- Archived never-synced customer/product/category/supplier lifecycles have explicit create-first handling in the relevant handlers.
- Product create/archive already sends the complete product create payload before the deterministic delete follow-up.
- Customer create/archive uses a deterministic archive operation after the create establishes the server ID.

### A6 - archived category/supplier create payload mismatch

Status: FIXED_PENDING_CI

Business impact:
An archived category or supplier created locally before first cloud delivery could reach the create handler with deletedAt set. The handler selected category.create / supplier.create but used the delete-shaped payload whenever isDelete was true. That could omit required create fields and cause the authoritative create to fail or create incorrectly, preventing the subsequent delete/archive convergence.

What was found:
category_sync_handler.dart and supplier_sync_handler.dart selected the create operation type for a never-synced archived row but used a payload containing only server_id and optional base_cursor.

What changed:
The create/update payload is now selected by operation type. Delete-shaped payloads are used only when the actual operation type is *.delete.

Regression coverage:
- Archived category test now asserts the create payload contains the category name and does not contain a server ID.
- Archived supplier test now asserts the create payload contains the supplier fields and does not contain a server ID.
- The existing tests continue to verify the deterministic :delete follow-up and create sequence used for delete OCC.

CI:
Run 36102975452 is currently in progress for HEAD ddc221e4cb2fe1818f19146eae7ab0bdf0a50257.

### Section 1 remaining audit questions

Still to prove before Section 1 can be marked complete:
- create -> update -> delete/archive ordering for every mutable entity, including same-transaction and in-flight replacement cases
- whether any entity can be locally deleted/archived without an explicit queue mutation that the handler understands
- handler finalization writes after network awaits, including server-ID assignment and sync-status settlement
- stale queue item completion against a newer queue row/entity mutation (A3 remains open)
- cash-drawer create -> close ordering and replacement
- customer ledger repayment lifecycle versus server-derived ledger entries
- return lifecycle where approval/completion is local-only versus cloud-authoritative
- any entity-specific create/update coalescing or permanent-failure edge case not covered by the generic queue tests

Do not mark Section 1 complete until these paths have evidence.


### 2026-09-25 A3 stale-finalization continuation

Status: FIXED_PENDING_BROAD_LIFECYCLE_COVERAGE

Verified:
- Every production sync handler that calls `markSynced` now passes the durable queue operation ID.
- Stock movement finalization uses the same operation identity through `markSettled`.
- Repository finalization runs the queue-identity/newer-mutation check inside the same SQLite transaction as the final sync-state write.
- If the supplied operation ID no longer exists, the completion is treated as stale: the server ID may be recorded, but the local mutation is not marked settled.
- A newer queue mutation keeps the local row pending rather than allowing an older in-flight response to settle it.
- SyncEngine removes the queue row only after the handler returns successfully, so the operation identity is present during normal finalization.
- Regression coverage proves the missing-operation and newer-queued-mutation fences for products.
- Customer repayment rejected-state canonical recovery now uses the customer's local ID for the queue freshness fence and also refuses settlement when its own queue identity is missing.
- CI run 36115719336 (run #2211) passed after the customer-repayment fence correction.

Remaining A3 proof:
- Add/verify entity-specific stale-finalization coverage for the financial/lifecycle handlers, especially cash drawer close, customer repayment, return, sale, and stock movement.
- Verify create→update and update→archive/delete in-flight replacement behavior across every mutable entity.

### 2026-09-25 lifecycle findings

Cash drawer:
- Open and close are distinct durable queue operations.
- Opening and closing in one local transaction sequence produces create first, close second.
- A close cannot sync until the local shift has a server ID, so create must establish the server identity first.
- First-cloud seeding adds the create task before a close task for an already-closed, never-synced shift.
- Repeated close calls are rejected locally once closed, preventing duplicate close mutations.
- Full in-flight create→close regression coverage is still required.

Customer ledger:
- Customer credit-sale and refund-adjustment ledger entries are server-derived/local projections and are not queued as independent client repayment commands.
- Customer repayments are the explicit client mutation: local balance/ledger entry and outbox row are created in one transaction.
- A rejected repayment attempts canonical customer recovery, fenced against a newer local customer mutation.
- A repayment's finalization is fenced against newer ledger mutations and missing operation identity.
- Dedicated adversarial repayment concurrency tests remain to be added/verified.

Returns:
- The authoritative cloud mutation is completion via `return.create`; approval/rejection is currently local-only.
- Completion restores local inventory and applicable customer credit locally, then queues the authoritative cloud return command in the same transaction.
- The return sync handler requires the original sale and referenced products to have server identities before submission.
- Rejected returns attempt canonical product/customer recovery behind the newer-mutation fence.
- The code explicitly documents that the backend has a separate approve endpoint, but approval/rejection is not currently pushed by this client sync pass.
- Therefore return approval/rejection convergence is **PARTIAL**, while completed-return cloud synchronization is implemented.

Next audit focus:
- Dependency ordering and starvation/deadlock behavior in `SyncQueue` + `SyncEngine`.
- Then adversarial lifecycle tests for create→update→archive/delete and in-flight replacement across all mutable entities.


## 2026-09-25 queue-lifecycle audit continuation

### Section 1 findings after full enqueue/repository/handler sweep

Status: PARTIAL

Verified lifecycle behavior:
- Customer, category, supplier, and product support create/update plus archive/delete semantics through their update queue operation. An archive performed before first push is handled as create-first, followed by a deterministic archive/delete command.
- Customer additionally supports explicit restore. Restore clears deletedAt and enqueues an update, so archive -> restore is represented by a newer durable mutation rather than an in-place queue rewrite.
- Expense supports create/update only; there is no repository delete/archive operation.
- Income record supports create only; there is no outbound update/delete/archive operation.
- Location supports create only on the client; delete/update are pull/server reconciliation concerns.
- Expense category supports create only in the client repository; delete/update are not represented as outbound client mutations.
- Stock movement is create-only by design; sale movements are server-derived and transfers are currently unsupported by the cloud command path.
- Sale is create-only in the outbound queue; local sale creation and its queue entry are transactional.
- Return is create-only at the cloud-command layer and becomes queued only on completion. Approval/rejection remains local-only in this client sync pass.
- Cash drawer has separate create/open and close operations. Closing requires a server identity, preventing close from overtaking create.
- Customer ledger has only explicit repayment as a client mutation. Credit-sale/refund-adjustment ledger entries are server-derived projections.

Queue replacement proof:
- Update operations receive a fresh queue identity on each local mutation.
- Therefore update -> archive/restore while an earlier update is in flight leaves a newer queue identity behind for the newer local state.
- Generic SyncEngine coverage proves an old handler cannot delete a newer replacement queue row.
- Repository-level product coverage proves an old completion cannot settle when its queue identity is missing or when a newer mutation is queued.
- Entity-specific adversarial lifecycle coverage is still incomplete, so Section 1 remains PARTIAL.

Concrete finding confirmed during this sweep:
- A5 Product operation identity remains open. ProductSyncHandler helper methods accept nullable operation IDs and fall back to the entity local ID when called without a queue operation ID. Production queue dispatch currently passes the queue ID, but the helper contract still permits an unsafe local-ID operation identity and is not yet hardened to make the queue identity mandatory.
- This is a concrete API-level safety gap, not a proven current queue-dispatch failure. It remains deferred until the audit inventory phase reaches the Product helper call graph and the full fix pass begins.

### Dependency/starvation audit result

Status: PARTIAL -> ENGINE SCHEDULING PROVEN

Inspected:
- lib/sync/sync_queue.dart
- lib/sync/sync_engine.dart
- lib/sync/sync_triggers.dart
- test/sync/sync_engine_test.dart
- test/sync/sync_queue_test.dart

Verified:
- Dependency-blocked work is deferred rather than permanently failed.
- A prerequisite that appears later in the same drain can succeed and cause the dependent item to be retried in that drain.
- Dependency/reference writes use priority 0 while sales/financial operations use priority 1.
- A blocked item does not prevent unrelated later queue items from being attempted.
- Automatic retry is supplied by periodic sync triggers, connectivity changes, foreground resume, and post-cycle enqueue follow-up.
- Concurrent runOnce calls share one in-flight cycle.
- A local mutation committed during an active sync cycle is intentionally deferred until the current push/pull cycle finishes, protecting the base-cursor ordering boundary.
- There is no concrete starvation/deadlock defect identified in the inspected engine scheduling path.

Remaining dependency proof:
- Server-side dependency graph/RPC prerequisites still need to be audited against the client priority model.
- True cross-runtime/background scheduling behavior still belongs to the process-death and operational reliability sections.

### Next audit focus

Continue Section 1/2 with adversarial coverage for:
1. cash drawer create -> close while create is in flight;
2. customer repayment finalization/recovery while a newer customer mutation is queued;
3. return completion/rejection recovery while product/customer mutations change in flight;
4. stock movement response reconciliation while a newer local stock mutation is queued;
5. sale finalization/rejection recovery under newer product/customer mutations;
6. create -> update -> archive/restore replacement across the remaining mutable entities.

Do not mark Section 1 complete until those entity-specific boundaries have evidence.


### A3 lifecycle finding: stock movement success can overwrite newer local stock

Status: CONCRETE FINDING — NOT YET FIXED

The stock movement handler performs two local effects after the network command returns:
1. it calls ProductRepository.reconcileStockLevel() with the server-returned current_stock;
2. it then calls StockMovementRepository.markSettled() with the queue operation ID.

The second step is A3-fenced, but the first is not.

The local stock movement repository deliberately applies each new stock-in/stock-out/adjustment immediately to ProductStockLevels and marks that stock projection pending before enqueueing the movement. Therefore, if movement A is in flight and movement B for the same product/location is committed locally before A returns, A's server response can write A's older current_stock into ProductStockLevels before markSettled() notices that a newer stock-movement queue item exists.

That means the queue row itself remains correctly pending, but the visible local stock projection can temporarily regress to the stale A result. This is a real partial-success stale-finalization defect and is more specific than the already-fixed movement queue-settlement fence.

Required fix later:
- protect the server-current-stock reconciliation with the source stock-movement operation identity/newer-mutation check inside the same SQLite transaction boundary, or otherwise make the reconciliation conditional on the source operation still being current;
- add an adversarial regression where movement A is in flight, movement B changes the same product/location stock, A returns an older current_stock, and the local projection must not regress;
- retain the existing markSettled queue-identity fence.

This finding is recorded for the fix phase; the audit remains in the inventory/proof phase.
