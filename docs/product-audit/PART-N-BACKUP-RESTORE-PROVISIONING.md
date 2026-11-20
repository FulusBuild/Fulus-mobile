# Part N — Backup, Restore, and Provisioning

**Status:** Deep source audit complete; interrupted-restore startup recovery and honest backup-location wording are fixed in the PR #237 with regression coverage. Restore/importer suites pass. Fresh-install physical Android restore and process-death validation remain unverified.
**Baseline:** `main` at `04403935748d3c36894480d62655a0b06585ddf0`
**Audit branch:** `codex/part-mn-sync-restore`
**Audit date:** 2026-11-20
**Environment:** Windows PowerShell; Flutter 3.44.9; no Android device attached to this worktree. Production Supabase and real business data were not used for mutation testing.

## Scope and trace

Part N covers authoritative cloud snapshot construction and authorization, local import ordering and schema translation, destructive restore atomicity, owner and employee identity mapping, device registration/readiness, sync cursor handoff, and post-restore reconciliation.

The main owner restore path is:

`authenticated owner session → CloudRestoreApi.restore_snapshot → fulus-restore membership/role check → owner snapshot RPC → business-bound response → CloudRestoreCoordinator maintenance fence and transaction → CloudRestoreImporter ordered row import → owner/session normalization and foreign-key verification → durable cursor/bootstrap reconciliation → normal sync`.

The employee path uses a separate location-scoped snapshot contract. Device registration remains installation-specific and is re-established after authentication rather than imported as business data.

Inspected the restore API/function, snapshot RPC references and migrations, coordinator/importer, employee restore/session flow, device registration, sync bootstrap/readiness, maintenance lease, and restore/multi-device tests. The coordinator checks for pending outbox operations and unresolved conflicts before replacing local state, checks the snapshot business ID, preserves the authenticated owner identity for cashier foreign keys, applies all local import/session/cursor changes inside the protected transaction, and verifies foreign keys before commit. Failures roll back the local replacement.

## Findings and dispositions

### P15-001 — Owner identity was not preserved during snapshot import

**Severity:** High
**Status:** Fixed in source; coordinator regression included; current full Flutter CI passed.

The coordinator now passes `ownerCloudUserId` into the importer. A regression restores an owner-attributed sale and checks that the owner row remains present. The local restore coordinator/importer suites were part of the 150-test focused run; CI also passed the full Flutter suite on the current source lineage.

### X-001 — Restore and sync needed a maintenance boundary across SQLite file replacement

**Status:** Source/protocol fixed; cross-process test passes in Linux CI; physical Android lifecycle evidence remains open.

Restore holds an exclusive sidecar file lock across closing/replacing/reopening the SQLite file. Normal sync takes a shared sidecar lock before its database lease. This keeps the fence valid even when the old database containing the logical maintenance row is replaced. The GitHub Flutter suite passed the cross-process regression. On this Windows machine, the test harness cannot start nested Flutter safely because the parent test process holds the native SQLite asset DLL; this is a test-runner/platform limitation and is recorded in Part M.

### M-001 — Historical E2E snapshot failure (cross-linked)

**Status:** Current server snapshot path verified by live multi-device CI; historical failure is not reproducible in current E2E. See [Part M](PART-M-SYNC-AND-MULTI-DEVICE.md) for the E2E request-count observation. Actual client-side import on a fresh Android install remains unverified.

The user-provided failure was `restore_snapshot failed with HTTP 500 / RESTORE_SNAPSHOT_FAILED`. The current run completed snapshot retrieval and checked the final canonical customer balance and sale fields. The Edge Function logs raw RPC details server-side but intentionally returns a generic error to clients; the original response does not identify the underlying database error.

## Automated and CI evidence

The shared M/N focused command and generated-code setup are recorded in [Part M](PART-M-SYNC-AND-MULTI-DEVICE.md). That combined restore/sync suite reported **150 passed, 1 skipped, 1 failed**; the only failure is the Windows cross-process test harness's inability to start nested Flutter while native assets are in use. Restore coordinator/importer/employee restore tests passed in that run. Targeted Dart analysis reported **No issues found**.

Fulus Mobile CI run **44741737242**, on PR #235 head `2ebd4caa1e1e8a31b641e51678035d7c11cef87c`, passed the full Flutter tests, live sync contract, and live multi-device convergence workflow. That multi-device scenario includes one authenticated `restore_snapshot` request and validates canonical snapshot data. CI did not run Android APK jobs.

No local Docker/Supabase CLI execution or production writes were performed. The live CI test uses the repository's configured QA/test environment and does not prove Android restore import behavior.

## Remaining evidence

- Fresh-install Android restore with synthetic QA data, including owner and employee identities, cashier-linked sales, staff permissions, and locations.
- Verify progress/readiness behavior on a large snapshot and after a network interruption or app process death.
- Verify restored cursor continuation and canonical post-restore convergence from the actual app on a second authorized device.
- Exercise unauthorized business and employee-location restore attempts against an isolated QA project; source and SQL guards are not a substitute for full runtime authorization evidence.
- Inspect server logs for a reproducible snapshot RPC failure if the historical 500 returns.

## Deep re-audit — 2026-11-20

The local-device pass traced snapshot creation (`VACUUM INTO` via a separate read-only SQLite connection), managed backup naming/pruning, Downloads export and rediscovery, import validation, staged restore validation, business binding, pre-restore snapshot, pending-outbox checks before and after maintenance acquisition, sidecar cleanup, database reopen/health probe, rollback, and restart gating. The cloud pass traced owner and location-scoped employee snapshot authorization through importer table ordering, identity remapping, money/schema conversion, foreign-key checks, durable cursor boundary, and device re-registration. Live production data was not changed. Android MediaStore behavior was not exercised on a device.

### N-001 — Backup screen promised a durable Downloads copy when export is best-effort

**Severity:** Medium
**Status:** Copy updated to describe the optional export honestly; no device validation yet.

`runAutoBackup()` creates a local snapshot, then prunes older automatic snapshots, then attempts a fixed-name Downloads export inside a silent catch. The app-wide trigger is activity-debounced and does not guarantee an initial export on every launch. The Backup screen previously said a Downloads copy “survives a reinstall” as though it always existed. The text now says it may exist and tells users to verify it before relying on an off-device copy. Physical MediaStore success, failure visibility, and reinstall rediscovery remain unverified.

### N-002 — Process death could leave no live database path during restore replacement

**Severity:** High
**Status:** Startup recovery added with three filesystem regressions; physical process-death test remains open.

Restore stages and validates the replacement, closes the app database under the maintenance fence, then renames the live database to a timestamped `.previous` file before moving the staged file into place. In-process exceptions roll back, but process death in that narrow rename interval leaves the live path absent. The native database resolver would then let Drift create a new empty database and did not scan for the preserved prior file. Startup now restores the newest correctly named `.previous` file only when the live path is absent; it never replaces a live database, and ignores `.tmp`/malformed files. Three tests cover recovery, no-overwrite after successful installation, and unrelated files. The safety file remains preserved if recovery rename itself fails.

### Current deep-pass test evidence

- `flutter test test/remote/cloud_restore_coordinator_test.dart`: **8 passed**, including pending queue/conflict, business binding, owner/session mapping, and fresh-install owner cases.
- `flutter test test/remote/cloud_restore_importer_test.dart`: **10 passed**, including staff/cashier ordering, money unit conversion, repeatability, malformed payload rejection, and snapshot-version rejection.
- `flutter test test/remote/cross_device_employee_restore_test.dart`: **1 passed**.
- `flutter test test/unit/backup_engine_test.dart`: **11 passed**.
- `flutter test test/unit/database_restore_startup_recovery_test.dart`: **3 passed**.
- Targeted Dart analysis for changed app and test files: **No issues found**.
- Part M's broad `flutter test test/sync` is **278 passed, 1 skipped, 1 known Windows subprocess-harness failure**; see the Part M test record.

Local native backup repository integration tests do not currently exercise actual filesystem staging, SQLite integrity rejection, MediaStore export, or rollback against a real app database. The new startup recovery test exercises the file selection/rename logic on temporary files, not Android process death. Supabase restore authorization was source-reviewed and covered by existing CI evidence; no local CLI/container or production mutation was used in this pass.

No release-readiness conclusion is made from the source, local tests, and live API evidence recorded here.
