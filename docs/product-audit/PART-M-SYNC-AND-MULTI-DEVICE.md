# Part M — Sync and Multi-Device

**Status:** Historical source findings revalidated and fixed; focused suite has a Windows subprocess-harness failure; live sync and multi-device CI passed; physical Android convergence remains unverified.
**Baseline:** `main` at `65ef6460f5ed6d20306b34ba509623cd028118c3`
**Audit branch:** `codex/part-mn-sync-restore`
**Audit date:** 2026-11-20
**Environment:** Windows PowerShell; Flutter 3.44.9; no Android device attached to this worktree. No production business data was accessed or changed.

## Scope and trace

Part M covers durable outbox enqueue and ordering, push/pull cycles, cursor persistence, canonical reconciliation, pending-local-mutation fencing, idempotency, conflict resolution, execution leases, stale-cursor recovery, device registration, and concurrent multi-device changes.

The principal path is:

`local repository transaction → durable sync_queue_items row → SyncEngine push/handler → authenticated Fulus API → cloud mutation/change feed → cursor-paged pull → entity-specific reconciler → Drift transaction guarded by SyncExecutionLease → local UI`.

Inspected the sync queue, engine, coordinator, execution lease, conflict resolver, trigger/service lifecycle, recovery path, typed reconcilers and handlers, multi-device E2E, related Supabase API/migrations, and focused sync/convergence tests. The current code retains queue operation identity and retry state, applies remote changes before durable cursor advancement, avoids overwriting queued local mutations, and serializes canonical apply with local repository writes through the SQLite execution fence.

## Findings and dispositions

### P14-001 — Employee pending mutation was omitted from canonical pull fencing

**Severity:** High
**Status:** Fixed in source; regression test is included; current full Flutter CI passed. Physical offline/retry convergence remains an evidence gap.

The common server-entity lookup now resolves employee server IDs to local IDs before checking for pending mutations. `test/sync/sync_queue_test.dart` verifies an enqueued employee update blocks canonical replacement. Cross-check of the registered entity handlers found no second missing mapping.

### P16-001 — Financial multi-device convergence and return integrity

**Severity:** Medium
**Status:** Source and server contract fixes revalidated; local two-SQLite and live multi-device regressions pass. Actual two-phone app convergence remains unverified.

The earlier duplicate credit reversal and return actor-binding defects have corrective migrations and financial-fidelity coverage. The current E2E registers a second device, checks feed visibility in both directions, exercises concurrent/replayed financial operations, and validates final server state. `test/sync/p16_multi_device_financial_convergence_test.dart` verifies canonical convergence into independent SQLite stores.

### M-001 — Multi-device E2E repeated full snapshot construction

**Severity:** Low
**Status:** Redundant E2E work removed and current snapshot request verified by live multi-device CI. The historical HTTP 500 is not reproducible; its causal link to repeated snapshots is unproven.

The final multi-device scenario now performs one full `restore_snapshot` request. Earlier requests only needed cursor/location information but constructed the full restore payload repeatedly, creating avoidable server work. The user-reported HTTP 500 is retained as historical evidence; the current live multi-device workflow completed its final snapshot and financial assertions successfully. Because the Edge Function intentionally masks Postgres details, the historical failure's exact underlying database cause cannot be reconstructed from the client error alone.

## Automated and CI evidence

Code generation:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' run build_runner build --delete-conflicting-outputs
```

Build runner completed and wrote 1,147 generated outputs. It emitted existing Drift duplicate-reference-name warnings. Dependency resolution modified `pubspec.lock`; that generated change was restored and is not part of the audit diff.

Focused suite:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\flutter.bat' test test/sync/sync_queue_test.dart test/sync/fulus_sync_coordinator_test.dart test/sync/sync_cursor_transaction_boundary_test.dart test/sync/sync_engine_test.dart test/sync/sync_process_death_replay_test.dart test/sync/sync_automatic_retry_integration_test.dart test/sync/sync_conflict_resolver_test.dart test/sync/sync_execution_lease_test.dart test/sync/sync_execution_lease_process_probe_test.dart test/sync/sync_triggers_test.dart test/sync/sync_restore_reconciliation_gate_test.dart test/sync/p16_multi_device_financial_convergence_test.dart test/remote/cloud_restore_coordinator_test.dart test/remote/cloud_restore_importer_test.dart test/remote/cross_device_employee_restore_test.dart
```

Result: **150 passed, 1 skipped, 1 failed**. The one failure is `maintenance fence survives SQLite file replacement across processes`: its test harness invokes `Process.run('flutter', ...)`, but Windows cannot launch the Flutter batch command that way. Retrying with `cmd.exe` reaches a nested Flutter invocation, which then fails because the parent test holds `build/native_assets/windows/sqlite3.dll` open. A Dart test-runner retry timed out. I reverted the experimental harness edit; no product-code failure was demonstrated. The matching full Flutter CI run passed on GitHub's Linux runner.

Targeted analysis:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' analyze lib/sync/sync_queue.dart lib/sync/sync_engine.dart lib/sync/sync_execution_lease.dart lib/sync/sync_conflict_resolver.dart lib/data/remote/fulus_sync_coordinator.dart lib/data/remote/cloud_sync_recovery.dart lib/data/remote/cloud_restore_api.dart lib/data/remote/cloud_restore_coordinator.dart lib/data/remote/cloud_restore_importer.dart lib/data/remote/cross_device_employee_restore.dart test/sync/sync_queue_test.dart test/sync/sync_engine_test.dart test/sync/sync_execution_lease_test.dart test/sync/p16_multi_device_financial_convergence_test.dart test/remote/cloud_restore_coordinator_test.dart test/remote/cloud_restore_importer_test.dart test/remote/cross_device_employee_restore_test.dart
```

Result: **No issues found**.

Fulus Mobile CI run **44741737242**, on PR #235 head `2ebd4caa1e1e8a31b641e51678035d7c11cef87c`, passed Flutter tests, static analysis, live sync contract, and multi-device convergence. APK jobs were skipped. The E2E result is live API evidence, not physical-device app evidence.

## Remaining evidence

- Two independent Android installations performing offline mutation → restart → reconnect → canonical convergence.
- Concurrent edits and conflict resolution through the actual app UI on authorized QA devices.
- Android process death/force-stop and WorkManager scheduling (also tracked by Part Q/Part O operational scope and historical P17-001).
- Windows execution of the cross-process lease test remains blocked by nested Flutter/native-asset file locking; Linux CI provides the passing automated evidence.

No release-readiness conclusion is made from this source, automated, and live-API evidence.
