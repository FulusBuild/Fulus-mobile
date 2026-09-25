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


### A3 failure-path finding: permanent rejection can mark newer local state as attentionNeeded

Status: CONCRETE FINDING — NOT YET FIXED

The stale-finalization hardening currently protects successful settlement, but some BusinessRuleFailure paths still write local sync state without checking the queue operation identity.

Confirmed call sites:
- ExpenseSyncHandler -> ExpenseRepository.markAttentionNeeded(localId)
- CashDrawerShiftSyncHandler -> CashDrawerShiftRepository.markAttentionNeeded(localId)
- IncomeRecordSyncHandler also uses markAttentionNeeded, although IncomeRecord has no client update operation.

The repository implementations for expense and cash drawer currently set syncStatus=attentionNeeded directly, without checking whether the rejected queue operation is still the current operation for that entity.

Adversarial consequence:
- Expense create can be in flight.
- A newer local expense update can replace/queue a newer operation identity before the create rejection returns.
- The old create's BusinessRuleFailure can still mark the expense row attentionNeeded, even though newer local work exists.
- Cash drawer has an analogous create -> close ordering boundary: a rejected old create can mark the shift attentionNeeded while the newer close operation remains queued.

The queue may remain durable, so this does not automatically delete the newer mutation, but the local entity state can incorrectly describe the newer mutation as permanently rejected/attention-needed.

Required fix later:
- Make permanent-rejection finalization operation-aware, with the same missing-operation/newer-mutation fence used by successful markSynced/markSettled paths.
- Add adversarial tests for expense create -> update and cash-drawer create -> close with the old request rejected after the newer queue operation exists.
- Do not weaken the existing permanent-rejection behavior when no newer mutation exists.

This is added to the A3 findings inventory and remains unfixed during the audit phase.


## 2026-09-25 production RPC/RLS audit evidence

Production project checked directly: Supabase project Fulus backend (bejcuvoxemwomcatgyxz).

Verified in the live database:
- The corrected fulus_api_update_expense base-cursor signature is deployed:
  fulus_api_update_expense(uuid,uuid,uuid,text,uuid,uuid,numeric,text,text,timestamptz,text,bigint,text).
- The deployed latest expense-update function is SECURITY DEFINER, uses search_path="", checks finance permission, active device ownership, idempotency/request hash, locks the idempotency row and target expense row, checks base-cursor conflicts, updates the expense/cash ledger, emits a sync change, and records the completed idempotency response.
- Older expense-update overloads exist in production but are not executable by service_role; only the latest base-cursor-aware overload has service_role EXECUTE.
- Across the live fulus_api_* inventory, no listed function is executable by anon or authenticated. Legacy overloads that remain present are not executable by service_role where a newer hardened overload superseded them.
- All inspected SECURITY DEFINER fulus_api_* functions have search_path="".
- The live mutation surface includes the expected customer, expense, location, sale, return, repayment, inventory, cash-drawer, income, device, and payment wrappers. The production inventory and ACLs match the service-role Edge Function boundary rather than direct client execution.
- Sync-related authoritative tables have RLS enabled. The inspected tables expose SELECT policies for business/member/permission-scoped reads, while mutation paths are primarily through SECURITY DEFINER service-role wrappers.
- diagnostic_events does not grant INSERT to anon/authenticated; the service role has INSERT. This removes the earlier concern that the absence of a diagnostic-events RLS policy necessarily exposed direct client insertion.

Security audit status:
- RPC execute surface: PROVEN for the inspected production function inventory.
- SECURITY DEFINER search_path hardening: PROVEN for the inspected fulus_api_* inventory.
- RLS surface: PROVEN for the inspected sync-related tables, with remaining tables/functions still to be inventoried.
- Full RPC transaction/idempotency/change-feed proof remains incomplete until each mutation wrapper is individually traced and compared with its current repository migration and production definition.

### 2026-09-25 A3/A5 fixes applied

Fixed:
- Stock movement server-returned `current_stock` reconciliation is now fenced by the originating `stock_movement` queue operation. A missing operation identity or newer stock movement causes the stale projection write to be skipped.
- Expense permanent-rejection finalization now accepts the queue operation ID and refuses to park the expense when that operation is missing or superseded by a newer mutation.
- Cash-drawer permanent-rejection finalization now has the same queue-identity/newer-mutation fence, protecting create→close replacement.
- Product sync helper methods now require the durable queue operation ID instead of allowing a local-ID fallback. Product create/update/delete submissions therefore cannot silently lose queue identity.
- Regression tests were added for stale stock projection and stale expense/cash-drawer rejection finalization; stock handler tests now assert operation identity propagation.

Pre-CI source review:
- Re-read all changed production files and relevant tests after edits.
- Verified the product helper no longer contains an `operationId ?? localId` fallback.
- Verified stock projection reconciliation remains callable without an operation ID for local product creation, while queue-driven stock sync passes the durable operation ID.
- Verified rejection fences execute inside SQLite transactions and check both operation existence and newer queue mutations.

Remaining audit:
- Complete adversarial lifecycle tests for sale, return, customer repayment, cash drawer create→close, and create→update→archive/restore across mutable entities.
- Trace every live `fulus_api_*` mutation wrapper for transaction/idempotency/base-cursor/change-feed/locking behavior against the production migration definitions.
- Verify cross-runtime/background process-death behavior of the sync execution lease and queue claims.



## 2026-09-25 customer repayment projection audit

### A3 finding: rejected repayment recovery must fence newer repayments

Status: FIXED

A rejected customer repayment restores the customer's canonical snapshot after a business-rule failure. The existing fence checked newer `customer` mutations, but a newer repayment has a different `customer_ledger` queue/entity ID and therefore was invisible to the generic same-entity queue check. That could allow an older rejected repayment to overwrite a newer optimistic repayment projection.

Fix:
- Inside the protected transaction, rejected-repayment recovery now checks newer `customer_ledger` queue rows and maps them to the same customer through their local ledger rows.
- Recovery is skipped when such a newer repayment exists.
- The existing customer-mutation fence remains in place.

Commit: dc9345f08c3295442a39db0321ced07bd3e8ee55

Next audit focus:
- Verify analogous cross-entity projection fences in sale/return rejection recovery, especially newer stock movements or repayments affecting the same product/customer projection.
- Continue the remaining RPC transaction/idempotency/change-feed and process-death audits.


## 2026-09-25 — Sale/return rejection projection race audit

### Finding: rejected sale/return recovery crossed entity streams without a sufficient freshness fence

The rejection paths were already protected against a newer mutation of the same product/customer entity. That was not sufficient for the projections they were repairing:

- a newer stock_movement can target the same product/location while having a different queue entity type and local ID;
- a newer customer repayment can change the same customer's balance while having customer_ledger as its queue entity type;
- a rejected sale can leave an optimistic local customer credit projection behind if its canonical customer snapshot is not restored;
- a rejected return can similarly need customer canonical recovery after its local refund adjustment.

The generic same-entity queue fence therefore did not fully prove that an old sale/return rejection response could not overwrite a newer projection.

### Fix applied

Sale rejection recovery now:

1. fences product canonical reconciliation against newer stock_movement queue rows for the same product/location;
2. reconciles the affected customer from the canonical customer snapshot;
3. fences that customer reconciliation against newer customer mutations and newer repayment ledger entries.

Return rejection recovery now:

1. fences product canonical reconciliation against newer stock_movement queue rows for the same product/location;
2. fences customer canonical reconciliation against newer customer mutations and newer repayment ledger entries.

The new checks run inside the existing protected SQLite transaction so the freshness decision and projection write share the same writer boundary.

SaleSyncHandler is now wired with CustomerRepository so rejected credit-sale projections can be restored from the authoritative customer snapshot.

### Regression coverage

Added sale-sync adversarial tests covering:

- rejected sale canonical customer recovery being suppressed by a newer repayment;
- rejected sale canonical product recovery being suppressed by a newer stock movement.

Production/test source review was performed before CI: changed files had balanced braces and the new queue-identity paths were inspected for malformed operation IDs or duplicate-brace syntax.

### Current status

**Fixed and CI verification pending for this iteration.**

### Remaining audit focus

Next boundary: complete the same cross-entity projection-race review for other rejection/failure paths, then move to the deeper server-side mutation-wrapper proof: transaction scope, idempotency locking, base-cursor conflict handling, and change-feed emission across every live fulus_api_* mutation command.

## 2026-09-25 — Location Switching & Isolation handoff

### 2026-09-25 — Location mutation isolation regression coverage

### 2026-09-25 — Location-safe restart/replay regression
Status: 🟢 targeted restart/replay proof added for pending sales.

Added a regression that:
1. creates a pending sale in location A;
2. confirms its durable outbox row exists;
3. models an app restart with a fresh auth repository and fresh sale sync handler while the persisted active location is B;
4. replays the pre-existing queue row; and
5. asserts the cloud payload still contains A's server location identity and the settled sale remains attached to local location A.

This extends the location boundary evidence across a fresh handler/repository lifecycle. It does not claim a literal OS process kill; the existing generic process-death replay test covers durable outbox survival, while this regression proves the location identity is preserved across the fresh-handler replay boundary.

Remaining location boundary work: offline cached/uncached switching, B-side pending mutations, location-scoped projection refresh across the major screens, and broader multi-location stock/report/cash-drawer isolation.

Status: 🟢 targeted regression coverage added for pending and in-flight mutations.

Added adversarial tests on `feature/location-switching` proving:
- A sale created under location A still submits `server-location-A` after the active location is switched to B before replay.
- A sale already inside `submitOperation` keeps its captured A payload while the active location changes to B before the network future completes.
- The completed sale remains associated with local location A after the in-flight operation settles.
- A pending stock movement created for A submits `server-location-A`, never B, using the persisted movement location.

This closes the previously identified end-to-end A→B→sync payload proof gap for the covered sale and stock-movement mutation paths. The broader location audit still requires restart/process-death replay evidence, offline cached/uncached switching, B-side pending mutations, multi-location projection isolation, and UI/report/cash-drawer refresh verification.


### Audit status

**AUDIT INVENTORY / IMPLEMENTATION HANDOFF**

Location switching is now designated as a separate production-readiness boundary. A dedicated implementation session may work on a branch such as `feature/location-switching` while the main audit continues independently on `main`.

The implementation branch must not be treated as production-ready merely because its feature tests pass. It must later be reviewed against this audit boundary and the cloud-sync invariants before merge.

### Production behavior Fulus should guarantee

Switching from location A to location B should be a controlled change of operational context, not merely a persisted ID or UI refresh.

Required behavior:

1. Persist the new active location atomically and make the new location the sole active operational context.
2. Preserve all pending mutations created under the previous location. Sync must use the mutation's durable location/entity identity, never the currently selected location at sync time.
3. Prevent stale in-flight work from location A from being interpreted as work for location B.
4. Reset/rebuild transient location-scoped state, especially carts, drafts, cash-drawer state, stock views, dashboards, reports, and location-scoped providers.
5. Keep business-global data global where appropriate: catalog/product definitions, categories, suppliers, customers, business settings, etc.
6. Load/use location B's local projections and, when required, reconcile B from cloud state.
7. Support safe offline switching when B's required local data is already available. If required data is unavailable offline, fail clearly rather than presenting misleading state.
8. Make the active location visible in the UI so users can tell which operational context they are using.
9. Handle switching during active sync, pending writes, open carts/drafts, and other transient operations without cross-location contamination.
10. After an app restart, restore the selected location safely and verify that the restored location still belongs to the current business/session.

### Current implementation evidence

The current app already has important location foundations:

- `ResolveActiveLocation` reads the session's active location, verifies it still exists locally, otherwise resolves/creates a default location, and persists the chosen local ID.
- `AuthRepository.setActiveLocationId()` persists the active location in the local session.
- `LocationRepositoryImpl` provides location listing/lookup, transactional local creation + queue insertion, server reconciliation, and stale-finalization fencing for location sync.
- The active-location Riverpod provider is intended to be the single source of truth for location-aware UI.
- Location-aware transaction/sync paths already carry location identity rather than relying solely on the currently selected UI state.

### Concrete finding: Sell CartCubit can outlive a location switch

The current Sell screen's cart-cubit creation path is effectively singleton-for-screen-lifetime:

`_ensureCartCubit(locationId)` returns the existing `CartCubit` when one already exists, without proving that the existing cubit's location ID matches the newly active location.

Potential sequence:

`Location A → Sell screen creates CartCubit(A) → user switches to B → activeLocationId changes → Sell rebuilds → existing CartCubit(A) is retained`.

This creates a production-risk boundary where the visible location and transient cart context can diverge. It does not by itself prove that a sale will be submitted to the wrong location, but it means location-context isolation is not currently proven.

**Required implementation/test direction:** a location switch must dispose/reset/recreate location-scoped cart state, or otherwise prove that the existing cart is safely transferable. Tests must cover A→B switching with an existing cart, including unsaved items/drafts.

### Required implementation audit checklist for the location branch

The implementation session should inspect and test, not assume, all of the following:

- active-location provider/state invalidation and notification;
- Sell/CartCubit lifecycle and draft-cart isolation;
- product stock queries and stock projections by location;
- stock-in/out/adjustment flows;
- sales and returns;
- expenses and income;
- cash drawer open/close and active-shift assumptions;
- customer ledger/credit projections where location affects the transaction;
- dashboard and finance statistics;
- reports and exports;
- search/filter screens;
- printer/receipt context where location identity/name is printed;
- offline switching and cached-data requirements;
- app restart after switching;
- switching while sync is running;
- switching with pending mutations from the previous location;
- concurrent local mutations around the switch;
- multi-device location state/reconciliation;
- permissions/membership for the selected location;
- deletion/archive of the currently active location;
- location IDs in queue payloads, API calls, and canonical reconciliation;
- prevention of using the active UI location as a substitute for durable mutation location identity.

### Required tests before merge

At minimum:

1. A→B switch with an empty cart.
2. A→B switch with an existing unsaved cart.
3. A→B while A has pending offline mutations.
4. A→B while an A sync request is in flight.
5. A→B while B has pending local mutations.
6. Offline A→B when B is cached.
7. Offline A→B when B is not cached.
8. App restart after selecting B.
9. Active location deleted/archived or no longer accessible.
10. Rapid A→B→A switching.
11. Concurrent mutation immediately before/after the switch.
12. Multi-location stock remains isolated.
13. Sync queue preserves A mutations after switching to B.
14. A mutation created in A cannot be submitted using B's location identity.
15. Location-scoped dashboards/reports/cash drawer state refresh correctly.

### Audit-side work that remains independent

The main audit will independently verify:

- whether every production mutation carries authoritative location identity;
- whether sync queue items remain location-bound through replay/retry/process death;
- server-side location membership and permission enforcement;
- location-scoped RPC transaction/idempotency/change-feed behavior;
- canonical pull/reconciliation isolation between locations;
- cross-location projection races;
- business/location switching interaction;
- process death during a location transition;
- production database invariants preventing cross-location records.

### Merge gate

Do not merge the location branch into `main` until:

- feature implementation is complete;
- targeted location tests pass;
- full CI is green;
- the audit-side location boundary is reviewed;
- no cross-location mutation/reconciliation race remains unaddressed;
- the implementation does not weaken existing business-switching, queue, idempotency, cursor, or canonical-reconciliation guarantees.

**Evidence standard:** 🟢 Proven = implementation + meaningful tests/production evidence + CI. 🟡 Partial = implementation exists but an important proof layer is missing. 🔴 Unknown = not verified or contradictory evidence.


## 2026-09-25 — Location durable mutation identity audit

### Finding

**Status: 🟢 IMPLEMENTATION-PROVEN / TARGETED REGRESSION COVERAGE STILL REQUIRED**

The location-switching audit traced the durable outbox and production sync handlers.

The sync queue does **not** store a separate mutable "current location" field. Instead, each queue row durably identifies the local entity by `entityType + entityLocalId`. The authoritative location is read from that persisted entity when the handler executes.

Verified examples:
- Sale sync resolves the server location from `sale.locationId`.
- Stock movement sync resolves the server location from `movement.locationId`.
- Expense sync resolves the persisted expense location.
- Income sync resolves the persisted income-record location.
- Cash-drawer sync resolves the persisted shift location.
- Return/sale stock reconciliation uses the persisted sale/movement location relationships.

This is the correct isolation direction: changing the active UI/session location does not rewrite the location on an already-created mutation.

### Important invariant verified

The active location is stored separately in the current session via `AuthRepository.setActiveLocationId()`. The sync handlers inspected for location-bound mutations do not use that active session location to construct the mutation's location identity.

Therefore the critical sequence is structurally supported:

`create mutation in A -> queue durable local entity -> switch active UI location to B -> replay queue item -> resolve location from the original entity -> submit A`.

The queue row itself remains unchanged by an active-location switch.

### Queue/in-flight boundary

`SyncEngine` selects durable queue rows and passes the exact queue item to the handler. The handler then resolves the entity by `item.entityLocalId`. Active-location switching does not replace that queue item or rebind its entity.

The existing queue/finalization hardening also means an old in-flight operation cannot simply settle a newer queue mutation after the queue identity has been replaced.

### Remaining proof gap

The architecture is sound for the inspected paths, but the audit should still add an explicit adversarial regression that demonstrates the complete boundary rather than relying only on source inspection:

1. create a mutation for location A;
2. leave it pending;
3. switch active location to B;
4. execute the queued handler;
5. assert the submitted payload contains A's server location ID;
6. assert B's active session ID was never substituted;
7. repeat after the mutation survives a restart/replay.

This test should cover at least sale and stock movement because they represent the two most important location-bound mutation classes.

### Classification

- **Durable mutation location identity:** 🟢 implementation-proven.
- **Active-location substitution during sync:** 🟢 no production path found in inspected handlers.
- **Queue identity surviving switch:** 🟢 implementation-proven.
- **End-to-end A→B→sync payload proof:** 🟡 targeted regression test still required.
- **Process-death A→B replay proof:** 🟡 already supported by durable queue architecture, but location-specific replay evidence remains required.

Do not add a redundant `locationId` to every queue row solely for this finding unless a later audit discovers an entity whose persisted location can be mutated independently of its durable mutation identity. The current queue design intentionally resolves authoritative foreign identities from the local entity.

## 2026-09-25 — Offline location switching regression

Status: 🟢 targeted offline switching coverage added.

Verified the location switch contract is offline-first:
- A→B succeeds when B already exists in the local location cache; switching does not require a network call.
- A→B fails clearly when B is not cached locally, which prevents activating an unknown/unavailable location while offline.
- A failed uncached switch leaves A as the active location and does not write B to the persisted active-location session.
- This preserves the required boundary: cached locations can be selected offline, while unavailable locations must be synced before activation.

Regression coverage added in:
`test/unit/switch_active_location_test.dart`

Remaining location audit work:
- B-side pending local mutations during A→B.
- location-scoped stock/projection isolation.
- dashboard/report/cash-drawer refresh after switching.
- switching during sync and other in-flight location-scoped operations.


## 2026-09-25 — Location-scoped dashboard projection audit

Status: 🟢 targeted dashboard isolation fix and regression coverage added.

The location-switching audit found a real projection gap in Home: the dashboard repository queried today's/yesterday's sales and cash-drawer status without a location predicate, and its low-stock notice summed stock levels across all locations. That meant switching from A to B could leave Home showing another location's sales, drawer state, or low-stock count.

Fixed on `feature/location-switching`:
- `DashboardRepository.getHeroState` now requires the active `locationId`.
- Sales totals and counts are filtered by that location.
- Open/closed cash-drawer state is filtered by that location.
- `getSecondaryNotices` now requires `locationId` and scopes low-stock projection to that location.
- Home resolves the active location for each dashboard load and reloads on the existing `dataRefreshSignalProvider` fired by a location switch.
- Existing recent-activity feed already resolves the active location inside `RealMoneyRepositoryImpl`, so it remains location-bound.
- Reports already listen to `dataRefreshSignalProvider` and pass the active location to cash-flow reporting.
- Cash-drawer repository methods require location IDs and the real money repository resolves the active location before drawer operations.

Regression coverage now proves:
1. A and B sales do not mix in the Home hero totals.
2. An open drawer in B does not make A appear open.
3. Low-stock projection only counts the requested location's stock levels.

Remaining location audit work: B-side pending mutations, broader multi-location stock/report coverage, and switching while sync/in-flight location-scoped UI work is active.


## 2026-09-25 — Multi-location stock and reports isolation

Status: 🟢 targeted stock/report isolation fixes and regression coverage added.

Audit found that the product catalog read paths were already location-scoped through `ProductStockLevels.locationLocalId`, and stock movement recording/reconciliation already binds product stock to the movement location. A new B-side pending mutation regression also proves a queued B stock movement cannot replay against active A.

A broader projection gap was found in `ReportsRepositoryImpl`: inventory stock, recent stock movements, employee sales, sales, customer sales, and finance aggregates needed an explicit location boundary. Reports now require a resolved `locationId`; the Reports screen resolves the active location and reloads the report futures when the location context changes. Inventory stock and movement queries, sales, customer sales, employee sales, finance sales/COGS/income/expenses, and prior-period finance values are location-scoped. Business-global customer balance/roster data remains intentionally global where the schema models it as business-wide rather than location-owned.

Regression coverage now proves:
1. Sales report for A excludes B sales.
2. Inventory report for A excludes B stock and B stock movements.
3. Existing dashboard tests prove A/B sales, drawer state, and low-stock projection isolation.
4. Existing product repository queries prove stock joins are location-bound.

Remaining location audit work: switching during sync/in-flight location-scoped UI work, plus a final compile/test/CI verification pass before merge. The PR remains unmerged until those checks are complete.


## 2026-09-25 — Location report drill-down audit

Status: 🟢 location-bound summary reports are wired; one drill-down caller gap was found and fixed.

During the independent location-isolation pass, the ReportsRepository interface had been widened so all report queries require an explicit location identity. The main Reports screen already supplied the active location, and the repository implementation scopes the location-bound report data.

A remaining caller in `SalesTransactionsScreen` still called `getSalesReport()` without the active location. That was corrected on `feature/location-switching` so the drill-down resolves the current active location before querying.

This matters because a summary report could be location A while its drill-down was otherwise capable of querying without an explicit location boundary.

Remaining location audit work:
- broader stock/projection isolation under A→B switching;
- cash-drawer isolation and refresh under A→B;
- in-flight switch/read race coverage across the major location-scoped screens;
- server-side location membership/access enforcement and canonical pull isolation;
- process-death during an actual switch transition.


## 2026-09-25 — Product stock pull/create location boundary

Status: 🟢 targeted product location fixes applied; broader backend contract remains to be independently verified.

Audit found two location-sensitive product paths. Product pull previously selected an arbitrary local location with `getSingleOrNull()` even though the product endpoint returns a single `current_stock` value. It now writes that projection to the persisted active local location instead of whichever location happens to be first in the Locations table.

Product create sync previously selected a stock row with `getSingleOrNull()`. A product can acquire another location's stock projection before its create mutation replays, so this was not deterministic. The handler now selects the oldest stock projection as the product's original initial-stock/location pair; later location stock changes remain separate stock-movement mutations. This reduces cross-location identity risk without conflating later stock with product creation.

Important remaining contract item: the mobile repository cannot prove from this repo alone which server location `GET /api/inventory/products`'s singular `current_stock` represents. The endpoint has no location query parameter. The active-location write is therefore the safe client boundary, but the backend endpoint contract should be independently verified before declaring multi-location product pull fully closed.


## 2026-09-25 — In-flight location-scoped stock/UI audit

Status: 🟢 client-side location boundary verified.

Inspected Stock overview, stock providers, record-stock flow, stock movement repository, Home, Reports, and the active-location refresh path. Stock products and movement streams are keyed by explicit location IDs. Stock mutations capture the active location when the user submits the mutation and persist that location on the movement before enqueueing. The repository updates the matching product/location stock projection transactionally, so an active-location switch after mutation creation cannot rewrite the mutation's location identity. Home and Reports reload their location-scoped projections from the active-location provider after a switch. The Sell flow separately rebuilds its CartCubit when the active location changes.

No additional client-side change was required in this pass. Remaining location boundary work is now primarily server-side canonical pull/access verification and final regression/CI verification. The product GET endpoint's singular current_stock contract still requires backend-side verification before that specific pull path can be considered fully closed.
