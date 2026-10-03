# Part 15 — Backup, Restore & Cross-Device Provisioning

**Status:** In progress  
**Baseline:** `main` after Part 14 and the background-lifecycle audit merge  
**Scope:** restore snapshots, importer ordering, destructive restore atomicity, employee provisioning, device registration/readiness, restore cursor, post-restore sync, and fresh-install recovery.

## Pass A — Structural inventory

Inspected:
- `lib/data/remote/cloud_restore_importer.dart`
- `lib/data/remote/cloud_restore_coordinator.dart`
- `lib/data/remote/cloud_sync_bootstrap_coordinator.dart`
- `lib/data/remote/cross_device_employee_restore.dart`
- `lib/data/remote/cloud_restore_api.dart`
- `lib/data/remote/employee_cloud_session_coordinator.dart`
- `lib/data/remote/fulus_device_registration.dart`
- `supabase/functions/fulus-restore/*`
- restore/importer/coordinator tests
- restore-related migrations and E2E paths

## Pass B — Restore importer and coordinator

The importer performs a destructive replacement of portable business data and validates snapshot version, required local columns, imported row counts, and SQLite foreign keys. The coordinator wraps the restore in an outer Drift transaction and a durable sync execution lease. It also refuses to destroy local business state while the outbox or unresolved conflict records are non-empty.

The importer invokes staff reconstruction after locations, before sales are imported, so restored cashier users can satisfy sale foreign keys. It also handles cloud/local schema translations for inventory movements, payments, returns, expenses, and audit events.

### P15-001

**Severity:** High  
**Status:** Fixed in source; regression test added; CI pending.

**File:** `lib/data/remote/cloud_restore_coordinator.dart`  
**Function:** `CloudRestoreCoordinator.restore`

**Observed behavior**

The coordinator passed `ownerCloudUserId: null` to `CloudRestoreImporter.importSnapshot`, even though it receives the authenticated owner's cloud ID.

That caused the importer to clear the existing `users` row for the owner before importing the snapshot. The staff restore path intentionally skips the owner, so a restored sale whose `cashier_user_id` references the owner could then be inserted before the owner user row was recreated by `_normalizeOwner`.

The importer already supports `preserveUserId`, and the coordinator's surrounding comments establish preservation of the authenticated owner as the intended invariant.

**Expected invariant**

The authenticated owner identity must remain present throughout business-row import so restored foreign keys can reference it. Owner/session normalization should update that preserved identity after the business image is imported.

**Root cause**

The coordinator explicitly passed `null` instead of `ownerCloudUserId`.

**Impact**

A fresh-device restore containing owner-attributed sales could fail with a foreign-key constraint violation during import instead of completing atomically.

**Fix**

Pass `ownerCloudUserId` through to the importer. The importer preserves that user row while clearing other local users. Final owner normalization then refreshes the restored identity and session.

**Regression test**

Added a coordinator regression that restores a sale with `cashier_user_id == ownerCloudUserId` and verifies both the restored sale and owner identity survive.

## Pass C — Failure and boundary audit

### Atomicity

The restore is enclosed in one outer Drift transaction. Pending outbox work and unresolved conflicts are checked before destructive clearing. Foreign-key validation runs before commit. A failure during import rolls back the destructive changes.

### Snapshot completeness and ordering

The snapshot contains business rows plus authoritative membership/role/permission data required for staff projection. The importer rejects unsupported versions, non-array table sections, non-object rows, and rows missing required local columns.

The restore snapshot also carries a sync boundary so post-restore reconciliation can resume from an authoritative change-feed boundary rather than an unrelated cursor.

### Employee provisioning

Employee cross-device restore is location-scoped for non-admin employees. The employee session coordinator reconstructs the local employee projection, permissions, active location, and current session from the authoritative claim and restored local location.

### Device registration/readiness

Device registration is physical-device state and is not imported as business data. The normal readiness path re-registers the device after authentication/restore, keeping device authorization tied to the current installation.

## Pass D — End-to-end trace

```
Auth/session
  → restore API / snapshot
  → transactional local importer
  → owner/employee identity projection
  → local session + business settings
  → device readiness
  → restore cursor / normal sync
  → canonical post-restore reconciliation
```

The restored local image must be complete and internally referential before normal sync is allowed to claim readiness.

## Remaining evidence

- Physical fresh-install restore on Android still requires runtime evidence.
- Post-restore cursor continuation and convergence require live-device evidence beyond source/unit tests.
- Part 16 separately stresses concurrent multi-device edits after restore.
- Android process-death/WorkManager evidence belongs to Part 17.

## Verification

- Source cross-check completed across importer, coordinator, employee provisioning, device registration, and restore API paths.
- Regression test added for owner-referenced sales.
- CI verification follows on this branch.
