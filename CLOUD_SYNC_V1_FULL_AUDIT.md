# Fulus Mobile - Cloud Sync V1 Full Audit Ledger

Audit mode switched to **full-audit-first** on 2026-09-25.

Scope: production cloud-sync correctness, durability, concurrency, crash/retry behavior, multi-device behavior, server idempotency, change-feed completeness, cursor/recovery, business switching/restore, and mutation integrity.

Out of scope: UI/UX.

## Method

1. Inventory the complete sync surface.
2. Trace every durable outbound mutation from local write -> queue -> handler -> API -> Supabase mutation -> change feed -> pull -> canonical reconciliation.
3. Trace destructive/local-reset paths and cloud restore.
4. Trace concurrency boundaries and every async gap that can cross a lease, transaction, queue identity, or optimistic-concurrency boundary.
5. Trace operation identity and server idempotency.
6. Trace every sync entity lifecycle.
7. Trace recovery, cursor, process-death, reconnect, and multi-device paths.
8. Record defects before fixing them.
9. After the audit ledger is complete, fix findings one at a time: prove -> minimal fix -> regression/E2E -> commit -> CI -> production verification where possible.
10. Re-audit the affected invariant after each fix.

Evidence levels:
- PROVEN: implementation plus meaningful regression/contract/production evidence.
- PARTIAL: implementation is present but an important proof layer is missing.
- UNKNOWN: not verified.
- FINDING: a concrete defect/race has been demonstrated from the implementation.

## Current repository boundary

HEAD: `b620d7b4539f3054c3551581c5b0580979f040d3`

Main sync surface inventory:
- 27 files under `lib/sync/`
- 42 files under `lib/data/remote/`
- 55 repository implementation/mapper files
- 7 Supabase Edge Functions
- 119 Supabase migrations
- 36 sync/remote tests
- 4 E2E/verification tools

Latest CI for the operation-identity fix is green.

## Existing proven protections

The continuation audit already established and regression-tested:

- One production sync coordinator construction and one canonical apply transaction boundary.
- Shared SQLite durable execution lease across foreground/background runtimes.
- Transaction-first lease ownership fence for canonical reconciliation.
- Stale queue completion cannot remove a newer replacement queue item.
- Stale pull pages cannot overwrite a newer durable cursor.
- Conflict resolution is lease-protected and revalidates the unresolved conflict after lease acquisition.
- Push-rejection canonical recovery is lease-protected.
- Rejected-operation recovery is fenced against newer/same-timestamp local queue mutations.
- Local business reset requires successful lease acquisition.
- Cloud restore requires the shared lease and blocks when pending queue/conflict state exists.
- Queue seeding revalidates server identity before inserting stale seed operations.
- Durable queue item IDs are the intended operation identity across retries.
- Expense-category sync was corrected to use `item.id` rather than `category.localId`.
- Server command idempotency uses durable idempotency rows and row locking on the audited command surface.
- Server-side operation request hashes prevent reuse of an operation ID with a different payload on hardened paths.
- Device/business/user binding has been hardened across the audited service-role wrappers.
- Change-feed/cursor and canonical reconciliation have dedicated tests and live sync E2E coverage.
- No claim of exactly-once local execution is made. Correctness is based on durable outbox identity, server idempotency, canonical reconciliation, and at-least-once replay.

## Full audit ledger

### A. Local execution coordination

Status: PARTIAL

Verified:
- `SyncExecutionLease.acquire()` retries for the configured timeout.
- `ensureHeldForTransaction()` performs a conditional UPDATE as the first protected transaction operation.
- Renewal is owner-scoped.
- Release is owner-scoped.
- SyncTriggers checks the boolean acquisition result and treats a competing runtime as a no-op.
- Local reset and restore check acquisition success.

Finding A1 - destructive reset/restore transaction does not use the transaction fence
Status: RESOLVED IN CODE, REGRESSION VERIFICATION PENDING

Evidence:
- `clearLocalBusinessData()` acquires the lease, then starts a separate Drift transaction whose first operations are deletes.
- `CloudRestoreCoordinator.restore()` acquires the lease, then starts a separate transaction whose first operation is a read of `syncQueueItems`.
- Both destructive transactions now call `ensureHeldForTransaction()` as their first database operation.
- A runtime can therefore acquire the lease, begin a deferred SQLite transaction, pause before its first writer statement, allow the lease to expire, and be followed by another runtime acquiring the lease. The old transaction can then continue into destructive writes.
- This is the same transaction/lease gap already proven in canonical apply, now found in the reset/restore boundaries.

Required proof/fix:
- Add the same writer-lock/ownership fence to both destructive paths.
- Add cross-connection takeover regressions for reset and restore.
- Verify that a takeover cannot complete while the protected transaction is active and that the old transaction cannot continue after ownership is lost.

Finding A2 - restore can race ordinary local mutation without an initial writer fence
Status: RESOLVED IN CODE, REGRESSION VERIFICATION PENDING

Evidence:
- Ordinary local queue insertion is intentionally lease-free.
- Restore begins with reads, then performs destructive import writes.
- The restore transaction now acquires the SQLite writer lock and validates lease ownership before the queue/conflict guard and importer writes.
- The restore transaction can then erase the newly-created local mutation.
- The intended invariant is that restore must exclude concurrent durable local mutation for the whole restore transaction, not merely check queue state at one read point.

Required fix:
- The restore transaction must acquire the SQLite writer lock and validate lease ownership before the queue/conflict guard and importer writes.

### B. Queue identity and lifecycle

Status: PARTIAL

Verified:
- Queue rows have durable IDs.
- Update coalescing replaces the queue row so a newer local edit gets a new durable operation identity.
- Blocked/conflicted rows can be superseded by a newer local mutation.
- Queue seeding revalidates server identity.
- Stale completion regression exists.
- Conflict rows retain operation identity.

Still to audit:
- Every entity lifecycle: create, update, delete/archive, create->update, create->delete, repeated updates, blocked->newer, conflict->newer.
- Delete/archive semantics for every handler.
- Whether any handler has a fallback operation ID other than the queue item ID on a production path.
- Queue priority starvation/deadlock.
- Dependency graph correctness.

### C. Sync handlers

Status: PARTIAL

Handlers inventoried:
- category
- customer
- customer_ledger
- expense
- expense_category
- income
- location
- product
- return
- sale
- stock_movement
- supplier
- cash_drawer_shift

Operation-ID invariant:
- Normal queue-driven submissions use `item.id`.
- Lifecycle follow-up operations intentionally derive a child identity such as `:delete` or `:archive`.
- Expense-category's previous violation was fixed and regression-tested.

Still to audit:
- Every fallback `operationId ?? localId` path.
- Every multi-step handler for partial success boundaries.
- Mark-synced timing relative to authoritative response.
- Rejection/canonical recovery for every entity.
- Entity-local-ID/server-ID mapping during replay.

### D. Server idempotency and command transactions

Status: PARTIAL

Verified in source:
- Idempotency claims are inserted with a unique business/key identity.
- Locked reads use `FOR UPDATE` before replay/mutation decisions on audited hardened wrappers.
- Request hashes reject operation-ID reuse with different payloads.
- Service-role command wrappers are the Edge Function boundary for the audited commands.
- Device/user/business scope has been hardened.

Still to audit:
- Every RPC reachable through `fulus-api`.
- Every legacy overload and its EXECUTE grants.
- Every wrapper's exact request hash coverage.
- Every mutation's transaction boundary around idempotency claim + business mutation + change-feed emission.
- Any remaining `ON CONFLICT DO NOTHING` path followed by an unlocked idempotency read.
- Return/sale/catalog/finance/inventory command parity.

### E. Change-feed completeness

Status: PARTIAL

Entities in client sync model:
- category
- customer
- customer_ledger
- expense
- expense_category
- income_record
- location
- product
- return
- sale
- stock_movement
- supplier
- cash_drawer_shift

Still to audit:
- Each authoritative mutation emits exactly the expected entity type and entity ID.
- Aggregate mutations emit all required dependent changes.
- Delete/archive is represented correctly.
- Sequence and timestamp are assigned atomically with the mutation.
- No mutation can commit without its required change-feed event.
- No duplicate event changes canonical reconciliation semantics.
- Latest migrations affecting customer balance, sale payment, return/catalog sequence, and stock movement timestamps need explicit end-to-end verification.

### F. Pull/cursor/recovery

Status: PARTIAL

Verified:
- Durable per-business cursor.
- Cursor is persisted after canonical application.
- Pull page cursor cannot advance past the requested durable cursor.
- Stale page revalidation exists.
- Cursor-too-old recovery exists.
- Failed reconciliation does not advance the durable cursor.
- No-forward-progress protection exists.

Still to audit adversarially:
- Duplicate sequence.
- Reordered sequence.
- Global sequence gaps.
- Empty page with hasMore.
- Already-acknowledged page with hasMore.
- Cursor ahead of response.
- Cursor persistence failure.
- Cursor-too-old recovery followed by delta failure.
- Recovery process death.
- Canonical batch latest-sequence semantics.
- Multi-entity aggregate latest sequence correctness.

### G. Process death and retry

Status: PARTIAL

Verified:
- Durable queue survives process death.
- Queue completion occurs after handler success.
- Server idempotency supports replay.
- Unit/model process-death regression exists.
- Automatic retry integration exists.

Still to prove:
- Actual device-level kill/restart boundary where practical.
- Network lost after server commit but before queue deletion.
- App killed during canonical apply.
- App killed during cursor persistence.
- App killed after restore import but before final commit.
- Background WorkManager restart behavior.

### H. Multi-device concurrency

Status: PARTIAL

Verified:
- Optimistic concurrency and base cursor exist on relevant server mutations.
- Conflict records are durable.
- Canonical conflict recovery exists.
- Multi-device convergence E2E has passed.
- Idempotency is device-scoped on hardened paths.

Still to audit:
- Every mutable entity with concurrent update support.
- Same entity, two devices, same base cursor.
- Device A commits while Device B has stale local state.
- Conflict followed by newer local mutation.
- Device revocation during in-flight command.
- Cross-device operation-ID collision.

### I. Business switching / restore

Status: PARTIAL

Verified:
- Restore is lease-gated.
- Restore blocks pending queue/conflicts.
- Restore import is transactional.
- FK verification is performed before commit.
- Readiness reconciliation occurs after restore.

Findings:
- A1 and A2 above require transaction-first fencing.

Still to audit:
- A -> B switching isolation.
- Cursor isolation by business.
- Failed B restore rollback.
- Post-restore delta pull.
- No stale A queue/conflict/cursor leakage into B.

### J. Data integrity

Status: PARTIAL

Still to audit against authoritative server contracts:
- negative stock
- duplicate stock levels
- impossible inventory movements
- sale/payment mismatch
- cash ledger mismatch
- credit ledger mismatch
- over-return
- orphaned aggregate children
- invalid business/device relationships
- stale devices
- malformed sync_changes
- duplicate idempotency keys
- unresolved conflicts
- permanently stuck queue rows

### K. Security / RPC surface

Status: PARTIAL

Verified in migration history:
- repeated SECURITY DEFINER hardening
- controlled search paths on current service wrappers
- service-role boundary for audited API wrappers
- device actor binding hardening
- legacy execute revocations

Still to audit:
- current effective grants for every mutation RPC
- overloaded legacy functions
- all SECURITY DEFINER functions
- RLS interaction
- diagnostic_events server-only intent
- Auth leaked-password protection configuration
- remaining RLS performance advisories
- service-role-only functions that can mutate cloud business data outside the audited API boundary

## Findings to fix after the audit ledger is complete

1. A1: add transaction-first lease fences to local business reset and cloud restore.
2. A2: ensure restore's initial writer fence prevents ordinary local mutation from entering the destructive restore gap.
3. Any additional concrete findings discovered during the remaining lifecycle/RPC/change-feed/recovery sweeps.

## Audit rule

No finding is marked resolved until implementation, regression/E2E evidence, and green CI are all present.

No APK build is part of this audit unless explicitly requested.

### A3 - stale handler completion can mutate local state after lease takeover

Status: FINDING

Evidence:
- The durable lease is acquired around the whole sync cycle, but individual handlers perform network awaits and then call local `markSynced`/`markSettled` writes.
- The engine only learns that the lease was lost at the cycle boundary via `ensureHeld()`; there is no ownership fence immediately before the handler's final local mutation.
- A suspended runtime can therefore resume after another runtime has acquired the lease.
- The stale handler can receive an idempotent/already-applied server response and then mark the local entity `settled`, assign a server ID, or otherwise finalize the row before the stale queue item is removed.
- Queue replacement protects the newer queue row from stale deletion, but it does not by itself protect the local entity row from the stale handler's finalization write.
- This is a distinct race from stale queue completion and must be closed explicitly.

Required proof/fix:
- Establish a transaction-scoped finalization fence that validates current lease ownership and the identity/currentness of the queue item before any handler marks local state settled/synced.
- Cover server-ID assignment, sync-status settlement, and stock/ledger settlement.
- Add a cross-runtime regression where runtime A is paused after server success, runtime B acquires the lease and replaces the queue mutation, then runtime A resumes. The newer local mutation must remain pending and the stale finalization must not settle it.

### A4 - business switch guard has a check-to-switch race

Status: FINDING

Evidence:
- `FulusConnectionState.selectBusiness()` awaits a guard, then changes `_selectedBusinessId` without holding a durable database/business-switch lock.
- Bootstrap's guard checks the queue before waiting for sync idle, waits, then checks the queue again.
- Ordinary local mutation enqueue is intentionally lease-free and can commit between that final queue check and `_selectedBusinessId = businessId`.
- The queue is durable and the local database is single-business, so a mutation created for business A can become associated with business B before the next sync cycle reads the selected business.
- This is a time-of-check/time-of-use race even though the normal happy path is guarded.

Required proof/fix:
- Establish an atomic business-switch boundary that prevents new old-business mutations from being committed between the final safety check and the context switch.
- Verify the boundary with a concurrent mutation regression.
- Verify A -> B switching cannot send an A queue item using B's credentials/context.

### A5 - operation identity fallback in Product update/delete helpers

Status: FINDING

Evidence:
- Queue-driven Product sync passes `item.id` into `_syncCreate/_syncUpdate`.
- The Product helper methods still accept nullable `operationId` and fall back to `localId` for update/delete submission.
- This is safe only if every caller is permanently guaranteed to provide the queue operation ID. The helper API itself does not enforce that invariant.
- The audit standard is that a durable queue mutation must never silently fall back to an entity local ID as its server operation identity.

Required fix:
- Make operation identity non-null for queue-driven mutation helpers.
- Preserve deterministic child identities such as `:delete` only when explicitly derived from the parent durable operation ID.
- Add regression coverage proving Product update/delete cannot submit with the entity local ID as operation identity.


## Audit continuation: operation identity and business-boundary sweep

### Operation identity sweep

The sync-handler operation-ID sweep was completed across all 13 production handlers.

Verified:
- Queue-driven create/update/close/repayment operations use the durable queue item ID.
- Category and supplier archive/delete follow-ups derive a deterministic child ID from the parent durable operation ID.
- Customer archive/update uses a deterministic archive operation identity derived from the queue operation.
- Stock adjustment and stock movement use the queue item ID even though they map to different server command types.
- Expense-category no longer falls back to the entity local ID; the queue item ID is asserted by regression test.

Remaining concrete issue:
- Product helper methods still accept nullable operation IDs and fall back to the entity local ID. This is tracked as A5 and remains unfixed until the audit ledger phase is complete.

### Business-boundary sweep

A4 remains a concrete finding. The current guard performs a final pending-queue check after waiting for sync idle, but ordinary local mutation enqueue remains intentionally lease-free. There is still a commit window between that final check and the selected-business assignment. Because the local cloud dataset is single-business, the switch must close that window atomically.

### Server/change-feed sweep observations

The current Edge API routes cloud mutations through service-role RPC wrappers rather than directly mutating business tables. Recent migrations also harden operation identity, device/user binding, optimistic-concurrency row locking, and SECURITY DEFINER search paths.

The customer balance change trigger now emits a customer canonical change when outstanding balance changes, covering balance mutations that previously emitted only ledger changes. Catalog tables have database-level sync-change triggers so direct server-side catalog mutations cannot silently bypass the feed.

No additional concrete server idempotency or change-feed race was promoted to a finding from this sweep. The remaining audit work is to prove the effective RPC grants, all mutation transaction boundaries, duplicate-event behavior, and the remaining process-death/data-integrity cases rather than infer correctness from migration intent.


## Handoff: areas still to audit in the next session

The full-audit-first phase is **not complete**. The next session should continue from this section and must not restart the audit or begin fixing A3/A4/A5 until the remaining inventory is audited.

### 1. Queue lifecycle and mutation coalescing
Audit every entity through the complete lifecycle:
- create -> update before first push
- create -> delete before first push
- repeated update coalescing
- update -> delete/archive
- delete/archive -> recreate
- blocked -> newer mutation
- conflict -> newer mutation
- permanent failure -> retry/new mutation
- queue item replacement while an older handler is in flight
- whether local entity sync status/server ID can be changed by an obsolete queue item

Entities to verify explicitly:
category, customer, customer_ledger, expense, expense_category, income_record, location, product, return, sale, stock_movement, supplier, cash_drawer_shift.

### 2. Handler finalization and partial-success boundaries
Continue the A3 investigation across every handler:
- exact point where server success becomes local settlement
- exact point where server ID is assigned
- all local writes after network awaits
- whether finalization revalidates queue-item identity/currentness
- whether stock, ledger, balance, inventory and aggregate writes have the same protection
- multi-step commands where one server mutation succeeds before a later local step fails
- deterministic child operation IDs and replay behavior

Do not assume the existing lease around the sync cycle is sufficient.

### 3. Product operation identity
A5 is already documented. Before fixing it, verify the entire Product helper call graph:
- create
- update
- delete
- archive
- any direct helper calls outside the queue handler
- deterministic child operation IDs
- tests that prove the queue item ID reaches the server API

Then fix only after the audit ledger phase is complete.

### 4. Queue priority, starvation and dependency graph
Audit:
- priority ordering
- dependency edges and dependency lookup
- cycles
- permanently blocked dependencies
- whether a high-priority item can starve lower-priority work indefinitely
- whether one blocked entity can prevent unrelated entities from draining
- retry scheduling and backoff interaction with dependency ordering
- conflict/permanent-failure parking and later release

### 5. Server RPC inventory and effective grants
Perform a complete inventory of all mutation RPCs reachable from `fulus-api` and related sync functions:
- every RPC name and overload
- every SECURITY DEFINER function
- effective EXECUTE grants
- revoked legacy overloads
- search_path hardening
- direct table privileges
- RLS policies
- service-role-only functions
- functions callable outside the intended Edge Function boundary

For each mutation RPC, document:
1. caller boundary
2. auth/device/business checks
3. idempotency claim
4. request-hash validation
5. row locking
6. business mutation
7. change-feed emission
8. transaction atomicity
9. response behavior on replay/conflict.

### 6. Idempotency transaction atomicity
Prove, rather than infer, that for every audited command:
- idempotency claim and business mutation are in one atomic transaction
- change-feed emission is in the same transaction where required
- a transaction rollback removes the idempotency claim
- a crash cannot leave a successful-looking idempotency row without the corresponding business mutation
- replay after commit returns the durable prior result
- same operation ID with a different payload is rejected
- cross-device/business/user operation-ID collisions cannot cross authorization boundaries

Pay special attention to any `ON CONFLICT DO NOTHING` followed by a non-locking read.

### 7. Change-feed completeness and event semantics
For every authoritative mutation:
- identify the exact trigger/RPC/function that emits `sync_changes`
- verify entity type and entity local/server ID
- verify sequence assignment
- verify timestamp semantics
- verify delete/archive representation
- verify aggregate mutations emit all dependent canonical changes
- verify no authoritative mutation can commit without its required feed event
- verify duplicate events do not regress canonical state
- inspect recent customer-balance, sale-payment, return/catalog-sequence and stock-movement changes explicitly.

### 8. Pull/cursor adversarial matrix
Add to the audit ledger the result of tests for:
- duplicate sequence
- reordered sequence
- sequence gaps
- empty page with `hasMore`
- repeated page with `hasMore`
- cursor ahead of server response
- stale page after another runtime/device advances the cursor
- cursor persistence failure
- cursor-too-old recovery
- failure during recovery
- process death during recovery
- latest-sequence selection when multiple changes for one entity are in a page
- multiple related entity changes with different sequences.

### 9. Process-death and retry matrix
Prove the following boundaries:
- server commits, client dies before queue deletion
- server rejects, client dies before canonical recovery
- client dies during canonical apply
- client dies after canonical apply but before cursor persistence
- client dies after restore import but before transaction commit
- client dies after restore commit but before readiness reconciliation
- WorkManager/background restart while a lease is held
- lease expiry during network suspension
- repeated retries after process restart.

Where device-level testing is impractical, explicitly record the strongest available integration/regression evidence and the remaining limitation.

### 10. Multi-device concurrency matrix
Audit each mutable entity for:
- two devices editing the same row from the same base cursor
- stale base cursor
- one device committing while the other is offline
- conflict followed by a newer local mutation
- server-side idempotent replay from another device
- device revocation during an in-flight command
- device deletion/deactivation during retry
- operation-ID collision across devices
- convergence after canonical pull.

### 11. Business switching isolation
A4 is already documented. Complete the surrounding audit:
- A -> B switch with an in-flight local mutation for A
- A -> B while sync is draining
- B -> A after failed switch
- selected business changes during background sync
- cursor storage isolation
- queue/conflict isolation
- credentials/device registration isolation
- stale A queue item after B is selected
- failed switch rollback and readiness state.

### 12. Cloud restore failure/recovery matrix
Beyond A1/A2:
- invalid snapshot
- missing required rows
- FK failure
- partial importer failure
- transaction rollback
- restore commit followed by readiness failure
- restore followed by delta pull
- stale cursor after restore
- pending conflict/queue created concurrently
- local mutation attempting to commit during restore
- process death before and after restore commit.

### 13. Data-integrity invariants
Verify against authoritative server contracts and database constraints:
- negative stock prevention
- duplicate/negative inventory quantities
- sale/payment totals
- cash drawer balance
- customer credit/repayment balance
- over-return prevention
- return quantity limits
- orphaned sale/return/ledger children
- impossible status transitions
- duplicate server IDs
- business/device ownership
- malformed sync-change rows
- unresolved conflict rows
- permanently stuck queue rows.

### 14. Security and effective RLS surface
Audit current effective database behavior, not only migration history:
- all RLS policies on sync-related tables
- all SECURITY DEFINER functions
- all EXECUTE grants and revoked overloads
- service-role-only mutation paths
- diagnostic/event insertion
- device registration/revocation
- cross-business access attempts
- cross-user access attempts
- malformed bearer/device combinations
- search_path and function ownership assumptions
- Auth configuration relevant to production sync security.

### 15. Operational/reliability surface
Audit:
- network timeout behavior
- HTTP retry classification
- 4xx vs 5xx handling
- rate-limit handling
- server busy/SQLite busy handling
- lease acquisition timeout behavior
- renewal failure behavior
- logging/diagnostics for lost lease and permanent failures
- retry/backoff persistence
- background scheduling overlap
- whether failures can leave the sync engine permanently paused.

### 16. Final audit closure
Only after all areas above have been inspected:
- update A-K statuses with evidence levels
- add every newly proven finding to the findings list
- distinguish concrete defects from unproven risks
- record exact tests/E2E evidence and limitations
- confirm the audit ledger itself reflects the current HEAD
- then begin fixes in priority order, one finding at a time
- every fix requires regression/E2E evidence and green CI before the next finding.

### Next-session starting point

Start at **Section 1: Queue lifecycle and mutation coalescing**, then proceed through Sections 2-15. Preserve A3, A4 and A5 as open findings. Do not mark any area complete merely because the implementation looks intentional. The next session should cite exact files/functions/tests for each conclusion and append newly discovered findings to this ledger.
