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
Status: FINDING

Evidence:
- `clearLocalBusinessData()` acquires the lease, then starts a separate Drift transaction whose first operations are deletes.
- `CloudRestoreCoordinator.restore()` acquires the lease, then starts a separate transaction whose first operation is a read of `syncQueueItems`.
- Neither transaction calls `ensureHeldForTransaction()` as its first database operation.
- A runtime can therefore acquire the lease, begin a deferred SQLite transaction, pause before its first writer statement, allow the lease to expire, and be followed by another runtime acquiring the lease. The old transaction can then continue into destructive writes.
- This is the same transaction/lease gap already proven in canonical apply, now found in the reset/restore boundaries.

Required proof/fix:
- Add the same writer-lock/ownership fence to both destructive paths.
- Add cross-connection takeover regressions for reset and restore.
- Verify that a takeover cannot complete while the protected transaction is active and that the old transaction cannot continue after ownership is lost.

Finding A2 - restore can race ordinary local mutation without an initial writer fence
Status: FINDING

Evidence:
- Ordinary local queue insertion is intentionally lease-free.
- Restore begins with reads, then performs destructive import writes.
- Without an initial writer fence, a local mutation can commit in the deferred-transaction gap or after the queue/conflict guard read but before restore's first write.
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
