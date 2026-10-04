# Fulus Sync Architecture Simplification Audit

**Status:** Source-level simplification is complete. The public facade, internal runtime boundary, cloud-session bootstrap coordinator, service-owned readiness state, and final call-path ownership audit are closed. Remaining work is production/runtime evidence only.  
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

`SyncTriggers` remains an internal lifecycle/event adapter. Its responsibilities are now bounded to:

- observing app lifecycle and connectivity;
- periodic/recovery trigger timing;
- entering the internal readiness/runtime gates;
- delegating restore fencing;
- scheduling device/session readiness recovery;
- forwarding requests into the internal runtime.

Push/pull sequencing and stale-cursor recovery live in `SyncCycleRunner`; readiness serialization, restore fencing, connectivity coalescing, and same-runtime cycle serialization live in their dedicated internal gates. `SyncTriggers` is no longer an application-facing synchronization authority.

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

**Latest simplification:** cloud/session bootstrap orchestration has been extracted from bootstrap.dart into CloudSessionBootstrapCoordinator, entered only through SyncService.bootstrapCloud(). SyncService now owns the readiness state (notReady → bootstrapping → ready/error) while FulusConnectionState receives only the UI-facing projection. Ordinary sync health errors remain separate from readiness.

---

### Second-pass ownership closure

The second-pass audit identified two semantic gaps that are now addressed in source:

1. Cloud bootstrap implementation — the large initializeCloudSync() policy function was removed from bootstrap.dart and moved into CloudSessionBootstrapCoordinator. The app root now constructs dependencies and wires the coordinator; it no longer owns the cloud lifecycle algorithm.
2. Readiness ownership — SyncService now owns readiness state and transitions. FulusConnectionState remains the reactive application projection and continues to own cloud session/business/device facts. Ordinary sync failures do not clear readiness.

The source-level Phase 5 ownership gate is closed. The final branch-specific call-path review confirms application lifecycle callers enter through SyncService; SyncTriggers remains internal; and readiness transitions are committed by SyncService. CI, Flutter tests, the live sync contract test, and multi-device convergence test are green. The remaining gate is explicitly runtime/production evidence.

## Third-pass ownership closure

The final source pass closed the remaining lifecycle leaks identified by FSA-006/FSA-007/FSA-008:

- `SyncService` contains configuration-listener startup failures and keeps the normal enable path awaitable.
- Readiness promotion/failure now occurs inside `SyncService.reconcileForReadiness()` and `SyncService.reconcileAfterRestore()`; UI/coordinator callers no longer call `markReady()` after reconciliation.
- WorkManager no longer reads the persisted sync-enabled flag directly; it bootstraps the app and requests work through `SyncService`, which owns the disabled-request boundary.
- Redundant cloud-bootstrap error wrapping was removed after the coordinator became the dedicated bootstrap implementation.

This closes the source-level simplification. Remaining work is verification and production evidence, not another orchestration extraction.

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

The facade is now the single public application entry point without changing the durable sync algorithms or their correctness guarantees.

### Phase 5 — consolidate lifecycle state **(complete at source level; runtime verification remains)**

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
- Same-runtime cycle/follow-up serialization now lives in the internal `SyncCycleExecutionGate`; `SyncTriggers` no longer owns the active-cycle future, follow-up future, or mutation-during-cycle flag.


#### Adapter-boundary checkpoint 

### Handler audit result

The handler audit found no safe generic extraction to make. Handler-level lease calls are not orchestration: they protect the atomic stale-completion/canonical-recovery decision against a newer local mutation. Removing that dependency would weaken invariant 14/15. Handler authorization checks likewise reject invalid cloud state at the entity boundary; retry classification remains in SyncEngine. These responsibilities remain intentionally split.

The remaining SyncTriggers constructor callbacks were audited against the target ownership model. They are integration seams for readiness, canonical pull/recovery, status reporting, device authorization recovery, and location-context hydration; they do not expose SyncTriggers to application callers or create a second lifecycle authority. They are intentionally retained because extracting them further would add fragmentation without removing an ownership decision or improving a correctness guarantee.

### Phase 6 — simplify handlers

**Audit status: complete.** No handler contains global sync orchestration that can be safely extracted without weakening entity-boundary authorization, lease-protected stale-completion safety, or SyncEngine retry ownership.

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

### FSA-001 — Lifecycle ownership was split before the final ownership pass

**Area:** lifecycle/orchestration

The pre-simplification architecture distributed lifecycle decisions across SyncTriggers, connection state, restore coordinators/screens, bootstrap, authentication screens, device readiness and WorkManager. PR #152 demonstrated a concrete consequence: the authentication → restore handoff needed nested cloud-onboarding fencing to prevent background sync from observing a partially initialized session.

**Resolution:** SyncService is now the public lifecycle boundary; restore fencing remains explicit and durable, while the underlying runtime primitives remain internal.

### FSA-002 — SyncTriggers remains internal with bounded adapter responsibilities

SyncTriggers remains an internal compatibility/lifecycle adapter. Its remaining operations are mechanics: platform lifecycle/connectivity observation, readiness-gate entry, restore-fence delegation, recovery scheduling, and forwarding requests into the internal runtime. Application callers no longer depend on it directly. Push/pull sequencing and stale-cursor recovery are in SyncCycleRunner; readiness initialization, recovery timing, restore fencing, connectivity coalescing, and same-runtime cycle/follow-up serialization are separate internal primitives.

**Resolution:** the final branch-wide call-path audit found no application-facing SyncTriggers lifecycle dependency. SyncService owns the public lifecycle decision and readiness state; SyncTriggers does not persist or decide application sync lifecycle.

### FSA-003 — SyncService now owns the readiness contract

The engine continues to provide durable queue draining, retries, conflict handling, auth/device recovery and diagnostics. FulusConnectionState still exposes the reactive `isSyncReady` projection, but it no longer owns readiness transitions. SyncService commits readiness transitions and projects them into FulusConnectionState. Ordinary synchronization health errors remain separate and do not clear readiness.

**Resolution:** the readiness contract is owned by SyncService without removing the connection-state projection required by the UI.

### FSA-004 — Cloud bootstrap is now isolated from application-root orchestration

CloudSessionBootstrapCoordinator now contains the cloud/session/device bootstrap policy: session restoration, membership resolution, business selection, device registration, local business binding, business-switch recovery, and readiness reconciliation. bootstrap.dart constructs and wires the coordinator but does not implement the bootstrap algorithm.

**Resolution:** SyncService.bootstrapCloud() is the only application-facing entry into that coordinator.

### FSA-005 — Pull coordinator should remain separate

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


### Adapter ownership ledger

The remaining internal adapter responsibilities have now been checked individually:

| Responsibility | Owner | Why it remains |
|---|---|---|
| Flutter lifecycle observation | SyncTriggers | Platform/event adapter only; it does not decide synchronization semantics |
| Connectivity observation | SyncTriggers + SyncConnectivityRunGate | Converts platform connectivity events into one coalesced service/runtime attempt |
| Periodic retry timing | SyncTriggers + SyncReadinessRecovery | Timing is an adapter concern; the recovery operation remains semantic |
| Readiness initialization | SyncReadinessGate | Serializes the existing readiness bootstrap callback without moving auth/business policy into a primitive |
| Device/session recovery timing | SyncReadinessRecovery | Defers recovery until the active cycle is clear |
| Restore reservation/fence | SyncService + SyncRestoreReconciliationGate | Service owns the public lifecycle decision; the gate owns only concurrent restore state |
| Push/pull ordering | SyncCycleRunner | Semantic cycle policy, independent of event source |
| Same-runtime cycle serialization | SyncCycleExecutionGate | Prevents duplicate cycles and coalesces mutations during an active cycle |
| Cross-runtime exclusion | SyncExecutionLease | SQLite durability is required for foreground/background process safety |
| Entity push/apply translation | SyncHandlers | Domain-specific responsibility; no global orchestration extraction identified |
| Queue drain/retry classification | SyncEngine | Durable execution authority |
| Canonical pull/cursor acknowledgement | SyncCoordinator | Cursor and apply-before-ack semantics must remain together |
| Production status/evidence callbacks | Bootstrap/service integration | These are integration seams for observability and connection-state projection |

No remaining SyncTriggers responsibility is currently justified as a second synchronization authority. Further extraction should require a concrete ownership ambiguity or duplicated guarantee; extracting primitives merely to reduce method count would increase fragmentation rather than simplify the architecture.

### Service lifecycle hardening

SyncService is now terminal after disposal. Bootstrap/request/lifecycle operations cannot re-enter a disposed runtime, and disposal is idempotent. This preserves the same terminal-lifecycle guarantee already established for the internal trigger runtime at the public application boundary.


## Production-evidence checkpoint

The existing regression suite already exercises the core sync invariants at the unit/integration level: durable offline mutation and restart, process-death replay, automatic retry, lifecycle/connectivity recovery, readiness/restore fencing, serialized follow-up cycles, and pull cursor/apply-before-ack safety. The remaining production-readiness gap is runtime evidence rather than another orchestration abstraction.

### Evidence matrix

| Scenario | Existing automated coverage | Remaining evidence |
|---|---|---|
| Offline sale -> restart -> queued push | Present | Real-device runtime verification |
| Process death -> WorkManager replay | Primitive/integration coverage present | Android runtime evidence required |
| Connectivity loss/recovery | Present | Real-device interruption check |
| Auth/session recovery | Readiness/recovery coverage present | Fresh-install/relogin runtime check |
| Two-device convergence | Coordinator/canonical tests present | Real two-device convergence run |
| Conflicting edits | OCC/canonical tests present | Real two-device conflict run |
| Location A->B with pending A mutations | Location/sync isolation coverage exists | Runtime switch with pending outbox |
| Restore -> reconciliation -> readiness | Restore fence/reconciliation tests present | Real restore smoke test |
| Device revocation/recovery | Trigger recovery tests present | Runtime authorization-loss scenario |
| Duplicate delivery / timeout after cloud commit | Engine/idempotency coverage present | Runtime fault-injection or observed replay evidence |

This checkpoint deliberately does not mark the runtime rows as proven. They remain explicit production-readiness evidence requirements; they do not represent another source-level orchestration simplification.

### FSA-006 — SyncService configuration reaction has an async error boundary gap

**Resolved.** SyncService now contains the fire-and-forget configuration listener's startup failure inside the service-owned readiness error state. Normal `enable()` still explicitly awaits the same coalesced runtime-start future, so callers receive the startup failure directly. The regression suite also covers an external/legacy configuration enable failure so the listener cannot create an unhandled lifecycle future.

### FSA-007 — Call-path ownership is not semantic ownership

**Resolved at source level.** Cloud bootstrap policy now lives in `CloudSessionBootstrapCoordinator`; readiness state and readiness transitions are committed by `SyncService`; restore/readiness reconciliation methods now promote readiness or record readiness failure inside the service instead of requiring screens/coordinators to mutate readiness state afterward. Employee restore, cloud connection, and cloud restore UI now request reconciliation rather than deciding readiness themselves.

Source coverage includes bootstrap/readiness ownership, restore overlap, device-authorization recovery, context/business-change reconciliation, startup failure, concurrent bootstrap, restore fencing, and configuration-enable failure. The source-level ownership audit is closed; full CI/regression verification and the explicitly listed real-device production evidence remain verification gates.

### FSA-008 — Background architecture remains conceptually correct

**Resolved/aligned.** WorkManager's worker now enters through `SyncService` without reading the persisted sync-enabled flag directly. `SyncService` owns the disabled-request boundary, so stale scheduled work after sync is disabled becomes a no-op inside the synchronization authority. The scheduler may still observe `SyncConfig` solely to register/cancel periodic OS work; it does not execute synchronization policy.

### FSA-008 — Background architecture remains conceptually correct

WorkManager and foreground execution still converge on the same durable synchronization stack through SyncService. This part of the target architecture is aligned and should not be redesigned.