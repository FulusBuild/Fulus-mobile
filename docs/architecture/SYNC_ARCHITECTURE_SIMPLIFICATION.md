# Fulus Sync Architecture Simplification Audit

**Status:** Phase 5 in progress — facade/runtime boundary established, lifecycle callers migrated, restore lifecycle ownership consolidated, and cycle orchestration extracted from the trigger adapter  
**Baseline:** `main` after PR #152  
**Audit branch:** `audit/sync-architecture-simplification`

## Objective

Simplify the Fulus synchronization architecture **without reducing capability or weakening correctness guarantees**.

This is an architecture audit, not a sync rewrite. The first goal is to identify where complexity is essential and where it is duplicated or spread across too many lifecycle owners.

## Senior-engineering conclusion

Fulus already has strong distributed-systems primitives:

- durable SQLite outbox;
- idempotent operation identity;
- dependency-aware queue draining;
- retry/backoff;
- server-side ordering via `sync_sequence`;
- cursor persistence and replay safety;
- canonical reconciliation;
- optimistic-concurrency/conflict handling;
- SQLite execution leasing across foreground/background runtimes;
- device authorization recovery;
- location-scoped mutations;
- WorkManager recovery;
- restore/bootstrap fencing.

The main complexity problem is **orchestration ownership**, not the underlying guarantees.

> **Keep the hard guarantees. Put the decisions in one place.**

The target is many simple callers feeding one synchronization authority, rather than many callers each knowing pieces of synchronization lifecycle.

---

## 1. Current architecture map

### Local mutation path

`Repository transaction → SyncQueue.enqueue → durable sync_queue_items → SyncEngine → SyncHandler → FulusSyncApi → Edge Function/RPC`

The durable queue is the correct foundation. It must remain.

### Outbound engine

`SyncEngine` currently owns:

- queue selection;
- dependency deferral;
- retry eligibility;
- handler dispatch;
- auth/device failure treatment;
- conflict classification;
- queue completion;
- diagnostic capture.

This is an appropriate central responsibility.

### Pull/reconciliation path

`FulusSyncCoordinator.pullAndApply → FulusSyncApi.pullChanges → canonical preparation → lease-protected local apply → cursor acknowledgement`

This is also a sound separation of concerns. Cursor acknowledgement after local application is a critical invariant and must remain.

### Trigger/orchestration layer

`SyncTriggers` is still an internal lifecycle/event adapter, but it currently coordinates more than pure event observation:

- connectivity;
- app lifecycle;
- periodic retry;
- queue-enqueue events;
- readiness entry;
- restore reconciliation;
- device authorization recovery;
- stale-cursor recovery;
- context/location reconciliation;
- execution leasing;
- push/pull cycle sequencing.

This remains the **largest simplification candidate**. The facade now hides it from application callers, but the adapter itself still contains synchronization lifecycle decisions that should progressively move into the service/engine boundary.

### Bootstrap

`bootstrap()` constructs and wires:

- database;
- repositories;
- cloud APIs;
- connection state;
- device registration;
- sync queue;
- sync handlers;
- canonical reconciler;
- sync coordinator;
- execution lease;
- SyncEngine;
- SyncTriggers;
- SyncService.

The wiring is explicit and testable, but the number of objects participating in lifecycle decisions is high.

### Authentication/restore lifecycle

Current cloud onboarding crosses:

`Auth screen → connection state → business/device resolution → restore coordinator/screen → SyncService → readiness → sync`

PR #152 fixed a real race at this boundary by making the onboarding fence nested/reference-counted.

That fix is correct and should be retained. It is also architectural evidence that lifecycle ownership is currently distributed.

### Background lifecycle

`WorkManager → fresh bootstrap → SyncService.request → waitForIdle → dispose`

Foreground and background use the same synchronization implementation, which is good. WorkManager should remain a trigger/recovery mechanism, not become a second sync implementation.

---

## 2. Essential complexity vs accidental complexity

### Essential — do not remove

| Capability | Why it stays |
|---|---|
| Durable outbox | Process death and offline durability |
| Durable operation IDs | Idempotency and stale-completion fencing |
| Atomic local mutation + outbox | Prevents lost local writes |
| `sync_sequence` | Deterministic server ordering/history |
| Persistent cursor | Safe incremental pull and replay |
| Apply-before-ack | Prevents skipped server changes |
| Canonical reconciliation | Multi-device convergence |
| OCC/conflict handling | Prevents silent data loss |
| SQLite execution lease | Foreground/background exclusion |
| Retry/backoff | Eventual recovery |
| Device registration | Installation authorization |
| Location identity on mutations | Prevents cross-location corruption |
| Restore/bootstrap boundary | Safe initial business state |
| WorkManager | Recovery when process is absent |
| Diagnostic evidence | Production observability |

These are distributed-systems guarantees. Removing them would make the architecture simpler only by making the product less correct.

### Accidental complexity — simplify

| Current complexity | Target |
|---|---|
| Multiple lifecycle authorities | One sync/session orchestration boundary |
| SyncTriggers makes sync decisions | Service owns semantic lifecycle; adapter observes events and delegates |
| Restore and sync partially own readiness | One bootstrap lifecycle |
| Connection state used as orchestration state | Internal session/readiness model |
| Auth screen manually coordinates cloud lifecycle | Cloud session bootstrap service |
| WorkManager calls trigger orchestration directly | WorkManager calls one sync entry point |
| Handlers receive coordination concerns | Handlers only translate/apply domain changes |
| Readiness scattered through callbacks | One readiness contract |
| Multiple concepts of “ready” | One coherent sync lifecycle |
| Direct consumers of low-level sync primitives | Public SyncService facade |

---

## 3. Target architecture

Conceptually:

```
UI / Repositories / Lifecycle / WorkManager
                    |
                    v
             SyncService
                    |
          +---------+---------+
          |                   |
   lifecycle/event adapter  SyncEngine
          |                   |
       Bootstrap         push / pull / retry
          |                   |
   auth/business/device   reconciliation
          |                   |
       restore                 |
          |                    |
          +---------+----------+
                    |
                    v
              Local SQLite
                    |
                    v
              Fulus Cloud
```

The key rule is:

> **Only SyncService/SyncEngine decides how synchronization executes. Everything else requests it.**

A small public contract is sufficient:

```dart
abstract class SyncService {
  Future<void> request();
  Future<void> bootstrap();
  SyncStatus get status;
}
```

The internal implementation can continue using the existing sophisticated components.

This is deliberately a **facade first, refactor second** strategy.

---

## 4. Proposed lifecycle model

Avoid treating these as independent application-wide readiness truths:

- authenticated;
- connection available;
- onboarding in progress;
- restore in progress;
- sync enabled;
- device registered;
- business selected;
- sync ready.

Instead, the cloud lifecycle should conceptually progress through:

```
SIGNED_OUT
    ↓
AUTHENTICATED
    ↓
BOOTSTRAPPING
    ↓
READY
    ↕
SYNCING

failure states are explicit and recoverable
```

Authentication is not synchronization readiness.

A restore failure must never be surfaced as “sign-in failed” when credentials are valid.

A useful future error taxonomy:

- `AUTHENTICATION_FAILED`
- `BUSINESS_RESOLUTION_FAILED`
- `RESTORE_FAILED`
- `DEVICE_REGISTRATION_FAILED`
- `INITIAL_PULL_FAILED`
- `SYNC_FAILED`

PR #152 remains necessary during migration because the existing lifecycle still has multiple owners.

---

## 5. Ownership rules

### SyncService owns

- bootstrap sequencing;
- readiness contract;
- public sync requests;
- sync lifecycle state;
- interaction between restore and sync;
- retry/recovery requests;
- delegation to the existing engine/adapter during migration.

### SyncEngine owns

- durable outbound queue draining;
- handler execution;
- retry classification;
- conflict classification;
- completion/parking.

### SyncCoordinator owns

- server pull pagination;
- local canonical application;
- cursor safety.

### SyncExecutionLease owns

- cross-runtime execution exclusion.

### SyncHandlers own

- entity-specific push/apply translation.

Handlers must not decide:

- when sync starts;
- whether the app is authenticated;
- whether WorkManager should retry;
- whether a lease is needed;
- whether restore is running;
- how the user should be notified.

### SyncTriggers owns during migration

- observing Flutter lifecycle and connectivity events;
- periodic/recovery trigger timing;
- the compatibility bridge into the existing sync cycle;
- internal serialization required to preserve current cycle safety.

It no longer owns the persisted sync-enabled configuration. `SyncService` owns
that configuration lifecycle and explicitly starts/stops the trigger adapter.
The adapter remains an internal implementation detail and is not an application
provider/API boundary.

**Next simplification:** extract the remaining readiness/recovery/cycle policy
from `SyncTriggers` into semantic service/engine operations, without changing
push/pull mechanics or lease guarantees.

---

## 6. Migration strategy

### Phase 1 — architecture mapping

**This document.**

Deliverables:

- component inventory;
- ownership map;
- essential vs accidental complexity;
- target lifecycle;
- invariants.

### Phase 2 — invariants

Create one canonical list of non-negotiable synchronization invariants and cross-reference every major component/test to them.

Minimum invariants:

1. Local SQLite is the UI source of truth.
2. Local mutation and outbox insertion are atomic.
3. Every mutation has a durable operation identity.
4. Operations are idempotent.
5. Server owns canonical ordering.
6. Pull applies before cursor acknowledgement.
7. Location identity never changes after mutation creation.
8. Only one sync execution authority runs a cycle.
9. Foreground and background use the same sync implementation.
10. Authentication is not equivalent to sync readiness.
11. Restore cannot expose partial business state.
12. Sync failure cannot masquerade as authentication failure.
13. Process death cannot lose a committed mutation.
14. Canonical pull cannot overwrite a still-pending local mutation.
15. Stale push completions cannot settle newer local state.

### Phase 3 — introduce the facade

Add `SyncService` as a compatibility facade over the existing implementation.

**No behavior change.**

Existing engine/coordinator/lease code remains intact.

### Phase 4 — route callers through the facade

Migrate, one boundary at a time:

- SyncTriggers;
- WorkManager;
- app lifecycle;
- mutation triggers;
- authentication completion;
- restore completion;
- device readiness.

At this stage the facade is becoming the single public entry point without changing sync algorithms.

### Phase 5 — consolidate lifecycle state **(in progress)**

After callers stop directly coordinating low-level readiness, simplify:

- onboarding fence;
- sync readiness;
- restore reconciliation state;
- connection/session state.

PR #152's reference-counted fence should not be removed until the new ownership boundary makes it unnecessary and equivalent regression tests exist.

Current progress:

- `SyncService` is the public synchronization boundary.
- Application callers no longer need `SyncTriggers` lifecycle configuration.
- `SyncService` owns `SyncConfig` listener registration and starts/stops the internal trigger adapter. `SyncConfig` is now only a persisted setting plus change notification; it does not own sync lifecycle behavior.
- Readiness recovery is requested through the semantic `recoverReadiness()` service operation.
- Restore fencing is exposed through service-level operations rather than trigger-specific UI calls.
- `SyncTriggers` no longer depends on the `SyncConfig` type.
- Location/context callers use `SyncService.refreshAfterContextChange()` rather than the internal trigger adapter.
- Queue mutation notifications are routed through the semantic `SyncService.onLocalMutationCommitted()` boundary rather than exposing the trigger adapter.
- `SyncRuntime` is now the internal runtime contract implemented by `SyncTriggers`; `SyncService` no longer depends on the concrete trigger type.
- Restore reservation state is owned by `SyncService`. Enabling sync for restore suppresses the normal runtime start until the authoritative post-restore reconciliation settles, then resumes the ordinary runtime for connectivity/retry recovery.
- Employee cloud restore now uses the same explicit restore lifecycle and does not advertise Sync Ready before post-restore reconciliation succeeds.
- Complete push/pull cycle sequencing and stale-cursor recovery now live behind the internal `SyncCycleRunner`; `SyncTriggers` retains trigger observation, readiness entry, recovery scheduling, and compatibility serialization rather than owning push/pull policy.
- The cycle runner preserves the existing SQLite lease, push-before-pull ordering, lease-loss handling, stale-cursor recovery, and post-recovery readiness callbacks.
- Readiness initialization serialization now lives in the internal `SyncReadinessGate`; `SyncTriggers` only supplies lifecycle events and the compatibility bridge to that semantic operation.
- Deferred device/session readiness recovery timing now lives in the internal `SyncReadinessRecovery`; `SyncTriggers` only supplies the current-cycle boundary and invokes the semantic recovery operation.
- Restore reconciliation fencing state and in-flight serialization now live in the internal `SyncRestoreReconciliationGate`; `SyncTriggers` only delegates the restore lifecycle boundary and reconciliation callback.
- Connectivity-gated run coalescing now lives in the internal `SyncConnectivityRunGate`; lifecycle/connectivity events share one in-flight readiness/sync attempt instead of maintaining a second orchestration state in `SyncTriggers`.

### Phase 6 — simplify handlers

Remove orchestration knowledge from handlers only after the facade is authoritative.

### Phase 7 — production evidence

Repeat the existing production-readiness evidence:

- offline sale;
- process death;
- background wake;
- token/session recovery;
- two-device convergence;
- conflicting edits;
- location A→B with pending A mutations;
- restore;
- restore failure;
- device revocation;
- reinstall/relogin;
- duplicate delivery;
- network timeout after cloud commit.

---

## 7. What we must NOT do

Do not:

- replace the engine wholesale;
- remove the outbox;
- remove `sync_sequence`;
- remove SQLite leasing;
- make cloud/network the UI source of truth;
- introduce a second background sync implementation;
- hide failures by weakening tests;
- replace deterministic lifecycle with arbitrary delays;
- remove restore fencing just because the code looks simpler;
- make handlers responsible for global sync state.

A smaller codebase is not automatically a simpler architecture.

---

## 8. Current findings

### FSA-001 — High architectural complexity, no correctness defect proven

**Area:** lifecycle/orchestration

The codebase has multiple legitimate components, but lifecycle decisions are distributed across SyncTriggers, connection state, restore coordinators/screens, bootstrap, authentication screens, device readiness and WorkManager.

PR #152 demonstrated a concrete consequence: the authentication → restore handoff needed nested cloud-onboarding fencing to prevent background sync from observing a partially initialized session.

**Recommendation:** keep SyncService as the public boundary while progressively moving lifecycle policy out of the internal adapter.

### FSA-002 — SyncTriggers remains the first refactoring target

SyncTriggers is correctly designed around a single cycle Future, but it still coordinates readiness, restore reconciliation, recovery scheduling and multiple trigger classes.

**Progress:** application callers no longer depend on it directly, and push/pull cycle sequencing plus stale-cursor recovery have been extracted into the internal `SyncCycleRunner`. The remaining safe work is readiness/recovery policy extraction one responsibility at a time, with existing trigger tests retained as regression coverage.

### FSA-003 — Existing SyncEngine is a strong core

The current engine already provides durable queue draining, retries, conflict handling, auth/device recovery and diagnostics.

**Recommendation:** preserve it and place a facade above it instead of rewriting it.

### FSA-004 — Pull coordinator should remain separate

The pull coordinator has valuable cursor/process-death semantics and should not be merged into entity handlers.

**Recommendation:** preserve the separation, but make it an implementation detail of the single sync authority.

### FSA-005 — Background architecture is conceptually correct

WorkManager and foreground execution converge on the same durable synchronization stack.

**Recommendation:** simplify the entry point, not the underlying implementation.

---

## 9. Definition of success

The simplification is successful only if:

- a developer can understand the sync entry point quickly;
- callers do not need to understand leases, cursors, retries or restore fences;
- there is one documented owner for every lifecycle decision;
- existing guarantees remain intact;
- all current sync tests continue to pass;
- production E2E remains green;
- no new race is introduced;
- foreground and background still use the same engine;
- offline-first behavior remains invisible to the user.

The final architecture should feel simple **from the outside** while remaining sophisticated internally.

> **Complexity should exist in one place, not everywhere.**
