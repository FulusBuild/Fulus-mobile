# Part 01 — App Bootstrap & Lifecycle

Baseline SHA: a71af8d4678c49f2dd5afa46018dffc0c4eaf799
Audit branch: audit/deep-code-part-01-bootstrap-lifecycle
Status: Code audit and CI verification complete for the audited scope; runtime/production evidence remains pending.

## Audit contract

Followed the master plan: Inventory → Trace → Inspect → Prove → Classify → Fix → Test → Cross-check → CI → Record.

## Inventory

Primary files inspected:
- lib/main.dart
- lib/app/bootstrap.dart
- lib/app/app.dart
- lib/app/app_shell.dart
- lib/app/providers.dart
- lib/app/router.dart
- lib/app/app_lock_gate.dart
- lib/app/auto_backup_gate.dart
- lib/app/restore_restart_gate.dart
- lib/sync/background_sync.dart
- lib/sync/sync_triggers.dart
- lib/sync/sync_queue.dart
- lib/data/local/database/app_database_lifecycle.dart
- lib/data/local/database/database.dart
- lib/data/remote/fulus_connection_state.dart
- lib/data/remote/fulus_diagnostic_uploader.dart

Adjacent restore files inspected:
- lib/data/repositories/backup_repository_impl_native.dart
- lib/features/more/settings/presentation/screens/backup_screen.dart
- lib/features/auth/presentation/screens/backup_restore_decision_screen.dart

Tests inspected:
- test/app/restore_restart_gate_test.dart
- test/sync/sync_triggers_test.dart

## Baseline

main was confirmed at a71af8d4678c49f2dd5afa46018dffc0c4eaf799.
The latest Fulus Mobile CI run for that SHA was successful: run 36979544060.
The master plan was read from branch docs/deep-code-audit-master-plan. The Part 01 and ledger files were not present on main at baseline.

## Trace

Foreground startup: main → ensureInitialized → global error capture → bootstrap → local session restore → dependency graph → ProviderContainer → runApp → SyncService bootstrap → background scheduling.

Bootstrap wires the local Drift database, auth repository, API clients, repositories, sync queue, sync handlers, canonical reconciler, sync coordinator, SyncEngine, SyncTriggers, and Riverpod overrides.

Background lifecycle: WorkManager callback → fresh bootstrap → SyncService.request → waitForIdle → SyncService.dispose → ProviderContainer.dispose → database close.

Restore lifecycle: BackupRepositoryImpl closes the live DB, atomically replaces the database file, reopens a fresh AppDatabase, then the UI sets a restart-required gate because existing repositories and sync handlers captured the old DB instance.

## Finding P01-001

Part: 01 — App Bootstrap & Lifecycle
Severity: Medium
Status: Closed in code; CI/runtime verification pending
Files: lib/sync/sync_triggers.dart; test/sync/sync_triggers_test.dart
Functions/classes: SyncTriggers.dispose, notifyEnqueued, syncNow, didChangeAppLifecycleState (internal adapter responsibilities)

Observed behavior:
dispose removed listeners, observers, subscriptions and timers and set _started to false. It did not make the object terminal. A later SyncQueue enqueue callback could still call notifyEnqueued, which could enter _runIfOnline and start another sync cycle.

Expected invariant:
Once a runtime service is disposed, later callbacks must not restart work or use dependencies that the owner is tearing down.

Root cause:
_started represented activation, not disposal. Public/internal entrypoints did not have a terminal lifecycle guard.

Impact:
A disposed foreground/background sync runtime could be re-entered after teardown. This is especially unsafe around the WorkManager teardown sequence, where the DB is closed immediately after trigger disposal.

Evidence:
Baseline call path was SyncQueue.setOnEnqueued(syncTriggers.notifyEnqueued) → SyncTriggers.notifyEnqueued → _runIfOnline. dispose only reset _started. Existing tests covered ordinary disposal calls but did not prove post-disposal inertness.

Fix:
Added a terminal _disposed flag. dispose is idempotent. start refuses to reactivate a disposed instance. notifyEnqueued, refreshAfterContextChange and lifecycle resume become no-ops after disposal. Explicit syncNow and restore reconciliation calls throw StateError after disposal.

Regression test:
Added tests proving a disposed trigger does not check connectivity or call SyncEngine.runOnce when later queue/lifecycle callbacks arrive, and that explicit syncNow is rejected after disposal.

Cross-check:
Checked the retry timer, connectivity subscription, readiness-recovery timer, config listener, lifecycle observer, SyncQueue callback, and WorkManager teardown path. No second disposal implementation was found.

## Deferred / partially proven

Restore versus active sync remains a cross-part risk. Restore closes the live database while SyncTriggers is an independent runtime holding direct references to the original DB. The restart gate protects business UI after restore, but source inspection does not prove that restore and an already-running sync cycle cannot overlap.

This is intentionally not patched speculatively. Parts 15 and 17 should reproduce restore during active push/pull/recovery, then introduce the smallest shared maintenance gate if the race is reproduced.

## Definition-of-done status

- File inventory: complete for the primary Part 01 boundary.
- Primary classes/functions: inspected.
- Call chains and lifecycle boundaries: traced.
- DB/network boundaries: inspected where bootstrap owns them.
- Concurrency/retry/disposal: inspected.
- Tests: reviewed and regression coverage added.
- Required tests: green in PR #117.
- Required CI: green in PR #117, run 36984821345.
- Android/runtime evidence: pending.
- Remaining uncertainty: restore versus active sync.

## Session handoff

Part: 01 — App Bootstrap & Lifecycle
Baseline SHA: a71af8d4678c49f2dd5afa46018dffc0c4eaf799
Audit branch: audit/deep-code-part-01-bootstrap-lifecycle
Current SHA: 02ed7bd0284ae3ee10e007d1b7ed85f0ac1652f2

### Completed
- Read master plan and confirmed current main baseline.
- Inventoried and traced the primary bootstrap/lifecycle boundary.
- Proved and fixed non-terminal SyncTriggers disposal.
- Added regression tests.

### Findings
- P01-001 Medium: disposed SyncTriggers could be re-entered by later callbacks. Fixed in code; verification pending.

### Fixed
- Added terminal disposal state and entrypoint guards.

### Still open
- Restore/active-sync maintenance coordination.

### Deferred
- Android process-death and restore runtime evidence.

### Evidence
- Baseline SHA a71af8d4678c49f2dd5afa46018dffc0c4eaf799.
- Baseline CI run 36979544060 succeeded.
- WorkManager teardown trace inspected.

### Tests
- test/sync/sync_triggers_test.dart updated.
- Full Flutter test suite passed in PR #117.

### CI
- Baseline main CI green.
- Audit branch CI green: run 36984821345.

### Runtime/production verification
- Pending Android evidence.

### Files inspected
- Primary bootstrap/app/sync/database files listed above.
- Restore/backup files and lifecycle tests listed above.

### Next recommended step
- Run targeted tests and required CI, then reproduce or formally defer restore-vs-active-sync with Parts 15/17.