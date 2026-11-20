# Part M — Sync and Multi-Device

**Status:** Deep source audit complete; two additional sync defects have source fixes and regressions in the PR #237. The filtered-feed coordinator suite passes; the full sync suite has one known Windows subprocess-harness failure. New SQL migration contract awaits disposable Supabase CI. Physical Android convergence remains unverified.
**Baseline:** `main` at `04403935748d3c36894480d62655a0b06585ddf0`
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

## Deep re-audit — 2026-11-20

The current pass mapped all 15 registered sync handlers and 46 files under `test/sync`, then traced queue persistence, retry/permanent-failure states, handler dispatch, HTTP authorization, database change-feed writes, location filtering, page/cursor parsing, canonical reconciliation, and maintenance fencing. The 15 handlers are `sale`, `customer`, `employee`, `customer_ledger`, `category`, `supplier`, `location`, `return`, `expense_category`, `cash_drawer_shift`, `expense`, `income_record`, `stock_movement`, `product`, and `product_photo`. No local-device or production-business mutation was performed.

### M-002 — Change-feed identity sequence could commit out of order

**Severity:** High
**Status:** Source migration and SQL contract test added; not yet applied to production or merged.

PostgreSQL identity allocation is not transaction/commit ordered. Two concurrent transactions for the same business could allocate sequences 41 and 42, commit 42 first, and commit 41 after a client had acknowledged 42. The client would then permanently miss 41. Current event writes flow through `_fulus_append_change` or `_fulus_catalog_change`; both now acquire a transaction-scoped advisory lock keyed by business before inserting into `sync_changes`. The lock is held through the caller's commit, while mutations for different businesses remain independent. `supabase/tests/sync_change_feed_ordering.sql` checks both helpers acquire the lock before insertion and that client roles cannot invoke the helper directly. Local PostgreSQL execution was unavailable (`supabase`, `docker`, and `deno` CLIs are not installed), so the migration-chain CI test is pending.

### M-003 — Filtered pagination could falsely report more and stall the client cursor

**Severity:** Medium
**Status:** Edge Function and coordinator fixes added; focused regressions pass locally.

The Edge Function scans location-scoped events in batches and can filter every row in a batch. A full raw batch followed by an empty/short query retained `has_more=true`; the response could contain no visible changes and a cursor that did not advance. The coordinator rejected that response, causing repeated scans. The API now clears `has_more` after reaching the feed end. The client accepts the server's scan cursor only after every returned visible change has applied; an empty filtered range advances directly when the cursor moves. It still refuses to acknowledge a page after a canonical apply failure. Tests cover empty filtered ranges, hidden rows after visible rows, failed apply, and pagination progress.

### Current deep-pass evidence

- `flutter test test/sync/fulus_sync_coordinator_test.dart`: **25 passed**.
- `flutter test test/sync/sync_cursor_transaction_boundary_test.dart`: **5 passed**.
- `flutter test test/sync`: **278 passed, 1 skipped, 1 failed**. The failure is `sync_execution_lease_test.dart: maintenance fence survives SQLite file replacement across processes`; Windows cannot launch nested Flutter while the parent process holds the native SQLite asset DLL. This reproduces the documented platform harness limitation; no new product assertion failed.
- `dart analyze lib/data/remote/fulus_sync_coordinator.dart test/sync/fulus_sync_coordinator_test.dart`: **No issues found**.
- No local Supabase migration-chain test, Deno type-check, Android device test, or production backend mutation was performed. The new migration contract is wired into `.github/workflows/supabase-migrations.yml` for disposable CI.

The prior baseline/CI evidence above this section is historical to its named PR/run. The M-002/M-003 changes need a fresh migration-chain run and full CI against their current PR commit before they can be called merged or deployed.

No release-readiness conclusion is made from this source, automated, and live-API evidence.
