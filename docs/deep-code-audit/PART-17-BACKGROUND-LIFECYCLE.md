# Part 17 — Background Execution & OS Lifecycle

## Scope

This audit covers the boundary between the Flutter foreground runtime, Android WorkManager background runtime, durable SQLite state, session restoration, sync execution leasing, and application lifecycle transitions.

Reviewed on the merged Part 14 baseline:
- `lib/main.dart`
- `lib/sync/background_sync.dart`
- `lib/sync/sync_triggers.dart`
- `lib/sync/sync_execution_lease.dart`
- `lib/sync/sync_engine.dart`
- `lib/app/bootstrap.dart`
- `lib/sync/retry_policy.dart`
- lifecycle/lease/sync tests
- Android manifest and WorkManager dependency configuration

## Architecture verified

### Foreground lifecycle

The application:
1. opens the durable Drift database during bootstrap;
2. restores the local session;
3. renders the Flutter tree;
4. starts SyncTriggers after `runApp()`;
5. starts WorkManager scheduling after the first frame.

This keeps cloud reconciliation out of the first-frame gate.

SyncTriggers observes:
- connectivity changes;
- periodic retry timer;
- app resume;
- local outbox enqueue;
- readiness/device authorization transitions.

The trigger object has an explicit terminal disposed state and does not re-enter after disposal.

### Background runtime

Android WorkManager uses the same durable database and sync engine rather than a separate background synchronization implementation.

The worker:
- initializes Flutter bindings;
- checks the persisted sync-enabled flag;
- calls the normal `bootstrap()`;
- invokes `SyncService.request()`;
- waits for the actual sync/recovery cycle through `waitForIdle()`;
- reports failures through the durable diagnostic logger;
- disposes the trigger/provider container and closes the background database.

The task is constrained to network connectivity and registered as unique periodic work.

Android WorkManager's minimum periodic interval is 15 minutes. The repository uses that minimum cadence, while foreground triggers provide more responsive retries. WorkManager timing remains system-controlled rather than exact. citeturn0search10turn0search2

### Cross-runtime exclusion

Foreground and background runtimes receive independent Dart isolates. SyncExecutionLease therefore uses SQLite rather than a Dart mutex.

The lease:
- has a short expiry;
- renews while held;
- can be taken over after expiry;
- verifies ownership before protected canonical writes;
- prevents a resumed/stalled runtime from continuing after another runtime has taken ownership.

Existing tests cover:
- single-owner acquisition;
- stale lease takeover;
- lease takeover fencing;
- resumed runtime stopping before pull;
- the lease covering the complete push/pull cycle.

### Durable outbox recovery

SyncEngine reads the durable queue from SQLite on every run. Retryable failures remain queued. Authentication/device-registration failures reset retry state rather than permanently parking the mutation. Permanent/business-rule failures are explicitly blocked.

Therefore process death does not depend on an in-memory queue surviving.

## Findings

### P17-001 — Medium — Background execution has an evidence gap, not a demonstrated source defect

The source path is internally consistent, but the repository has no direct automated test that executes the real WorkManager callback in a headless Android process and proves the complete sequence:

1. foreground process creates an offline mutation;
2. process is killed;
3. WorkManager starts a new runtime;
4. the new runtime opens the same durable database;
5. session restoration succeeds;
6. device/business readiness is restored;
7. the durable outbox mutation is uploaded;
8. canonical pull completes;
9. the queue item is removed;
10. the background runtime closes cleanly.

This cannot be honestly replaced by a unit test of `SyncTriggers`: the missing boundary is Android process/WorkManager behavior itself.

No source change is justified solely from this evidence gap.

## Cross-checks

### Scheduler registration

`main()` registers WorkManager after `runApp()`. Failure to initialize or schedule WorkManager is logged but does not block the application UI.

When sync is disabled, the unique periodic task is cancelled. When sync is enabled, the periodic task is registered with:
- unique name;
- network-connected constraint;
- exponential WorkManager backoff;
- 15-minute periodic cadence;
- update policy.

The current WorkManager package documents `update` as the recommended periodic conflict policy and says it preserves original timing while updating the specification. citeturn0search1

### Process death

The critical synchronization state is durable:
- outbox rows are SQLite-backed;
- sync cursor is persisted;
- sync lease is SQLite-backed with expiry;
- retry attempt state is persisted;
- conflict records are persisted.

In-memory state such as active Dart Futures and timers is intentionally disposable.

### App resume

Foreground resume calls the normal connectivity-gated sync path. This is complementary to WorkManager rather than a competing implementation.

### Connectivity loss

Connectivity events and the periodic retry path both re-attempt synchronization. A failed cycle does not terminate the trigger object.

### Authentication/session loss

SyncEngine treats authentication as a session-level condition. It does not permanently block the queue. Bootstrap/session restoration is responsible for recovering the session, after which the queued mutation becomes immediately eligible again.

### Device authorization loss

A revoked device registration clears the cached device authorization and schedules readiness recovery after the active cycle unwinds. This avoids recursively awaiting the current sync cycle.

### Lease expiry / runtime suspension

A suspended runtime can lose its lease. Protected transactions revalidate lease ownership before canonical writes, and another runtime can take over an expired lease.

## Platform limitation

WorkManager does not provide an exact execution time for periodic work. The 15-minute value is a minimum repeat interval, not a guarantee that synchronization occurs every 15 minutes. Android controls actual execution based on constraints and system scheduling. citeturn0search10

The application therefore correctly treats WorkManager as a recovery/safety mechanism rather than its primary real-time sync trigger.

## Remaining evidence

Part 17 should not claim physical process-death behavior fully verified until an Android runtime test demonstrates:

- offline mutation;
- process termination;
- WorkManager wake;
- session restoration;
- upload;
- canonical reconciliation;
- durable queue completion.

This evidence should be collected before final production-readiness closure.

## Conclusion

No high-confidence Part 17 source defect was found in the reviewed lifecycle/background architecture.

The key remaining item is **P17-001**, an Android runtime evidence gap. The implementation already has the necessary durable-state and cross-runtime coordination primitives, but source/unit tests cannot prove that the complete WorkManager process-death path works on a real Android runtime.

This audit therefore makes **no speculative architectural rewrite** and does not weaken existing tests.
