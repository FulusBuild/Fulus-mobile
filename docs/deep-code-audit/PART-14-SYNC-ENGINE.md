# Part 14 — Sync Engine

**Status:** In progress — source audit complete for the core sync runtime; CI/runtime verification pending  
**Baseline SHA:** 481d8a928ea0839b91ab5121dcc11eb370b9148f  
**Audit branch:** audit/part-14-sync-engine

## Scope

Audited the durable sync engine and its immediate coordination boundaries:

- `lib/sync/sync_queue.dart`
- `lib/sync/sync_engine.dart`
- `lib/data/remote/fulus_sync_coordinator.dart`
- `lib/data/remote/fulus_sync_api.dart`
- `lib/sync/sync_execution_lease.dart`
- `lib/sync/sync_conflict_resolver.dart`
- `lib/sync/sync_triggers.dart`
- `lib/sync/background_sync.dart`
- bootstrap wiring of queue, engine, coordinator, canonical reconciliation and lease
- outbound sync handlers and repository completion fences
- targeted sync queue/coordinator/process-death/retry/conflict tests

## Pass A — Structural inventory

### Durable outbound path

`repository transaction → SyncQueue.enqueue → sync_queue_items → SyncEngine → SyncHandler → FulusSyncApi → Edge Function/RPC`

The queue stores entity type/local ID, operation, priority, enqueue time, base cursor, actor identity, attempt/error state. UPDATE mutations receive a fresh queue identity so an older in-flight completion cannot settle a newer local mutation.

### Pull path

`FulusSyncCoordinator.pullAndApply → FulusSyncApi.pullChanges → prepare/canonical fetch → lease-protected local apply → cursor acknowledgement`

The coordinator deliberately applies changes before acknowledging the cursor. It treats `next_cursor` as pagination metadata rather than an acknowledgement.

### Runtime coordination

`SyncTriggers → SyncExecutionLease → push → pull → recovery`

Foreground and WorkManager runtimes share the SQLite lease. The lease is renewed while held and can expire after process death.

### Background path

`WorkManager → bootstrap → SyncService.request → waitForIdle → durable queue + pull/reconciliation`

The worker uses the same production sync stack rather than a separate implementation.

## Pass B — Function/class audit

### SyncQueue

Verified:

- enqueue is transactional
- durable actor identity is read from the local session inside the enqueue transaction
- business-switch barrier rejects mutations during context transition
- duplicate UPDATEs receive fresh operation IDs
- blocked/conflicted rows can be superseded by a newer local mutation
- first cloud connection can seed pre-existing local records
- seed insertion rechecks server identity inside the transaction
- dependency priorities normalize legacy rows
- pending canonical reconciliation is fenced by server entity identity

### SyncEngine

Verified:

- concurrent `runOnce` calls share one in-process Future
- failed items remain durable
- dependency-not-ready failures are deferred for another pass
- retryable failures retain queue rows and attempt metadata
- permanent/business-rule/validation failures become attention-needed
- auth/session failures reset retry state rather than permanently parking financial work
- device-registration loss invokes readiness recovery
- conflicts are durable and idempotently recorded
- successful completion removes the queue row and resolves superseded conflict state
- diagnostics preserve sync failure evidence without blocking queue progress

### FulusSyncCoordinator

Verified:

- cursor is business-scoped
- durable cursor is refreshed before and after network pulls
- server pages must be ordered
- global sequence gaps are accepted because the feed is business-filtered
- local apply precedes cursor acknowledgement
- process death can replay an applied change instead of skipping it
- empty page + `has_more=true` is rejected
- no-forward-progress pages are rejected
- cursor persistence is monotonic
- restore can explicitly establish an authoritative snapshot boundary

### SyncExecutionLease

Verified:

- SQLite, not a Dart mutex, is the cross-runtime coordination primitive
- lease acquisition is transactional
- expired leases can be taken over
- renewal extends only the current owner
- protected canonical transactions fence ownership before local writes
- newer queue mutations are checked under the same SQLite writer transaction

### SyncTriggers (internal event adapter)

Verified:

- connectivity, lifecycle, periodic retry, enqueue, readiness and recovery triggers converge on one sync-cycle Future
- an active cycle causes newly enqueued work to schedule a follow-up rather than race the current pull
- device revocation recovery is scheduled after the current cycle unwinds
- stale cursor recovery re-pulls after bootstrap
- restore/readiness paths avoid the documented readiness deadlocks
- lease loss aborts the cycle without continuing into later phases

## Pass C — Concrete finding

### P14-001

**Part:** 14  
**Severity:** High  
**Status:** Fixed in source; CI/runtime verification pending  
**Files:** `lib/sync/sync_queue.dart`, `test/sync/sync_queue_test.dart`  
**Function:** `SyncQueue.hasPendingMutationForServerEntity`

**Observed behavior**

The canonical pull path asks the queue whether a local mutation is still pending for each incoming server entity before applying the canonical row. The lookup handled sale, customer, customer ledger, category, supplier, location, return, expense category, cash drawer, expense, income, stock movement and product, but omitted `employee`.

A pending employee update could therefore be considered safe to overwrite by canonical pull even while its outbound queue row remained pending/retryable.

**Expected invariant**

A canonical pull must not overwrite an optimistic local entity while a durable outbound mutation for that same server entity is still pending.

**Root cause**

The entity-to-local-row lookup in `hasPendingMutationForServerEntity` had no `employee` branch.

**Impact**

A cloud employee change arriving during an offline/retry window could overwrite the local employee projection before the local employee mutation was accepted. Because employee data participates in the staff/roster projection, this could temporarily expose stale role/profile/location state locally and undermine deterministic convergence.

**Fix**

Added the missing `employee` server-ID → local-ID lookup to the common pull-side pending-mutation fence.

**Regression test**

Added a queue test that creates a server-identified employee, enqueues an employee update, and proves `hasPendingMutationForServerEntity(entityType: 'employee', serverId: ...)` returns true.

**Cross-check**

Employee repository `markSynced` was separately inspected. Its completion path already checks the current queue operation and newer employee mutations inside a Drift transaction, so the stale network-response race on the push side is already fenced.

The common pending-mutation lookup was cross-checked against all currently registered sync entity handlers; employee was the concrete missing entity type.

## Pass D — End-to-end invariant checks

### Durable outbox

**Proven in source:** local enqueue is transactional and queue state survives process termination because it is persisted in SQLite.

### Ordering

**Proven in source/tests:** dependency priorities place reference/catalog work before financial operations, and dependency failures are deferred within the same drain.

### Idempotency

**Proven in source:** operation IDs are durable queue identities and cloud mutations use those IDs; repository completion fences prevent stale completions from settling newer local state.

### Cursor safety

**Proven in source/tests:** changes are applied before cursor acknowledgement; cursor persistence is monotonic; replay after process death is intentionally supported.

### Concurrent runtimes

**Proven in source/tests:** SQLite lease coordinates foreground and WorkManager runtimes; canonical apply uses lease fencing inside the write transaction.

### Offline/online

**Partially proven:** durable queue and retry triggers exist and targeted tests cover retry/replay. Physical Android network/process-death behavior remains a release evidence gap.

### Multi-device convergence

**Partially proven:** canonical reconciliation, OCC and live multi-device convergence tooling exist. Full adversarial device/runtime breadth remains a later production/runtime evidence task.

## Tests reviewed

- `test/sync/sync_queue_test.dart`
- `test/sync/fulus_sync_coordinator_test.dart`
- `test/sync/sync_cursor_transaction_boundary_test.dart`
- `test/sync/sync_engine_test.dart`
- `test/sync/sync_process_death_replay_test.dart`
- `test/sync/sync_automatic_retry_integration_test.dart`
- handler-specific sync tests
- canonical reconciler tests
- conflict resolver tests
- live sync/convergence tooling

## Remaining uncertainty

1. Physical Android process-kill/force-stop plus offline mutation and WorkManager wake remains runtime evidence, not a Dart-only proof.
2. Broad adversarial multi-device conflict coverage remains partially proven and is explicitly shared with Part 16.
3. Background execution is platform-controlled; WorkManager cadence cannot be treated as exact scheduling.
4. Restore/maintenance overlap remains a cross-cutting boundary documented in `CROSS-CUTTING.md`.

## Changes in this session

- Fixed P14-001 employee pull-side pending-mutation fencing.
- Added targeted regression coverage.
- No speculative sync architecture rewrite performed.

## Next

Run targeted/full CI on the audit branch, inspect failures without weakening tests, then merge only after required gates are green. After merge, run the production/live sync evidence required for this part and close the audit record only when that evidence is available.
