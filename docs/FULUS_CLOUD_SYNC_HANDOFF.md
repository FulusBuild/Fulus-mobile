# Fulus Cloud Sync Hardening — Handoff

**Project:** Fulus Mobile  
**Repository:** `SanniMuhammed/Fulus-mobile`  
**Primary branch:** `main`  
**External APK build repository:** `FulusBuild/Fulus-mobile-build`

> This document is the persistent handoff for the current Cloud Sync hardening work. Do not treat the work as complete until every required cross-check below has actually passed.

## Non-negotiable working rules

- Do not declare the Cloud Sync hardening complete until **five independent cross-checks** pass.
- Green CI alone is **not** proof that Cloud Sync is complete.
- Avoid destructive rebuilds or broad rewrites when a focused fix is sufficient.
- Inspect the actual repository/backend state before relying on an earlier claim.
- After the cloud-sync architecture is complete and all five checks pass, build/install an APK and verify the real-device flow.

## Current CI situation

The latest known failing CI run was:

- Run: `34943350924`
- Commit: `e481fef52bbe39dd62cc6f2236183f3b6499a849`
- Failing job: `104297665975`
- Failure type: static analysis

The failure was eight analyzer errors caused by missing `SyncStatus` imports in:

- `test/sync/offline_sale_local_flow_test.dart`
- `test/sync/sale_sync_handler_test.dart`

The minimal fix was applied:

```dart
import 'package:fulus_mobile/data/local/database/tables.dart';
```

Fix commits:

- `0bc943c064112068a7f0bf669abc09ad23bf747a` — `fix: import SyncStatus in offline sale test`
- `32d9e189d71342a29439abe15c2004e74fb2bc10` — `fix: import SyncStatus in sale sync test`

**Required next action:** verify the CI run produced by these fixes. Do not assume it is green.

## Cloud Sync audit — current state

| Area | Current assessment |
|---|---|
| Local-first DB | Good |
| Durable sync queue | Good foundation |
| Retry/backoff | Good foundation |
| Supabase auth | Mostly good |
| Cloud business provisioning | Good after recent fix |
| Device registration | Good foundation |
| Sale push | Implemented / being hardened |
| Customer push | Legacy API path remains |
| Expense push | Legacy API path remains |
| Income push | Legacy API path remains |
| Return push | Legacy API path remains |
| Stock movement push | Mixed/legacy |
| Location sync | Separate legacy path |
| Server → device feed | Built but currently unwired |
| Restore | Implemented, lifecycle gaps remain |
| Sync activation after restore | Previously missing; readiness work is in progress |
| Dependency ordering | Partial |
| Error reporting | Too generic |
| Multi-device reconciliation | Incomplete |

## P0 requirements

### 1. Eliminate mixed Cloud transports

All Fulus Cloud sync writes must use the Supabase/Fulus Cloud API contract. There must be no silent dependence on `API_BASE_URL` or legacy API services for cloud sync.

Sale sync has already been moved toward Fulus Cloud-only behavior. The injected legacy `SalesApi` remains only for compatibility with existing callers/tests and must not be used for writes.

Remaining legacy transports must be audited and removed or deliberately replaced where a canonical backend command exists.

### 2. Make server → device reconciliation real

`FulusSyncCoordinator` already provides the conceptual cursor-based pull loop:

```text
cursor → pull changes → apply each change → advance cursor
```

It is not yet sufficient merely to have this class. It must be instantiated and wired into the running application.

Important rule: **never advance the cursor past a change that was not successfully and completely reconciled locally.**

### 3. Canonical pull/reconciliation for syncable entities

The target syncable surface includes:

- sales
- customers
- products
- categories
- suppliers
- returns
- expenses
- income
- stock
- customer ledger
- cash drawer
- locations

The change feed should be treated as a notification of what changed, not necessarily as a complete aggregate payload. In particular, the current sale change payload is summary-oriented and cannot reconstruct the complete sale aggregate by itself.

Preferred approach:

```text
change event
    ↓
identify entity + operation
    ↓
fetch canonical aggregate/state when required
    ↓
apply atomic local upsert/reconciliation
    ↓
only then advance cursor
```

### 4. Restore must automatically enter Sync Ready

After a successful restore, the application should reach Sync Ready only when all required conditions are true:

1. authenticated session
2. active business membership
3. registered/authorized device
4. sync enabled
5. initial online reconciliation completed successfully

A restored database must not be considered cloud-ready merely because the restore itself completed.

### 5. Startup Cloud initialization must be observable and race-safe

Important cloud initialization errors must not disappear through silent `catch (_) {}` blocks.

Current bootstrap work has moved toward diagnostic breadcrumbs and readiness-gated sync triggers. Continue this approach while replacing duplicated/legacy startup sync paths with the canonical coordinator.

## Current readiness work

`SyncTriggers` has been updated to accept:

```dart
Future<bool> Function()? isReady
```

Normal sync triggers are gated on readiness.

A restore-specific method exists:

```dart
Future<void> reconcileAfterRestore()
```

It is allowed to perform the initial reconciliation before the normal readiness gate becomes true, but requires connectivity and propagates reconciliation failures.

Bootstrap now passes:

```dart
isReady: () async => fulusConnectionState.isSyncReady,
```

The restore flow has been updated to perform initial online reconciliation before marking Sync Ready.

### Known cleanup

`reconcileAfterRestore()` currently performs some connectivity/stuck-sync checks redundantly because `_runIfOnline()` and the outer method both perform checks. This is functional but should be simplified after correctness is established.

## Current P0 gap in bootstrap

The bootstrap still contains legacy background sync calls similar to:

```dart
if (syncConfig.isEnabled) {
  unawaited(locationRepository.syncFromServer().catchError((_) {}));
  unawaited(businessSettingsRepository.syncFromServer().catchError((_) {}));
  unawaited(productRepository.syncFromServer().catchError((_) {}));
}
```

This is a remaining architecture gap. Important failures must not be silently swallowed, and these paths should eventually be consolidated under the canonical cloud synchronization architecture.

## Remaining legacy handler audit

Current sync handlers include:

- `SaleSyncHandler`
- `CustomerSyncHandler`
- `CustomerLedgerSyncHandler`
- `CategorySyncHandler`
- `SupplierSyncHandler`
- `LocationSyncHandler`
- `ReturnSyncHandler`
- `ExpenseCategorySyncHandler`
- `CashDrawerShiftSyncHandler`
- `ExpenseSyncHandler`
- `IncomeSyncHandler`
- `StockMovementSyncHandler`
- `ProductSyncHandler`

Known legacy paths from the audit:

- `IncomeSyncHandler` → `IncomeApi.createIncome`
- `LocationSyncHandler` → legacy location API/repository path
- `ExpenseCategorySyncHandler` → legacy expense-category API
- `CashDrawerShiftSyncHandler` → legacy cash-drawer API

Do not simply replace these with guessed endpoints. First establish the canonical backend contract and schema.

## Backend / Supabase state

Supabase project ref:

`bejcuvoxemwomcatgyxz`

Known healthy edge functions include:

- `fulus-provision-business`
- `fulus-api`
- `fulus-staff-api`
- `fulus-reporting-api`
- `fulus-restore`

**Important:** independently verify the active `fulus-api` version/source before relying on any earlier claim about its deployed version. A previous manual deployment/rewrite introduced uncertainty about whether all earlier routes were preserved.

### Known live canonical RPC primitives

The production database has been verified to contain canonical primitives for:

```text
accept_sync_operation(uuid,uuid,uuid,text,text,text,text) -> jsonb
apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid) -> jsonb
create_customer(uuid,text,text,text,numeric) -> jsonb
create_return_atomic(uuid,uuid,text,text,numeric,uuid,jsonb) -> jsonb
create_sale_atomic(uuid,uuid,uuid,text,timestamptz,numeric,numeric,numeric,text,text,uuid,jsonb) -> jsonb
record_customer_repayment(uuid,uuid,numeric,text,text,text,uuid) -> jsonb
record_expense(uuid,uuid,numeric,text,text,text,uuid) -> jsonb
register_device(uuid,uuid,text,text,text,text) -> devices
```

The accidental extra `accept_sync_operation` overload was removed.

A previously considered `reconcile_product_quantity` function was confirmed absent and should not be recreated without a correct contract.

### Backend contract gaps

The backend currently has canonical primitives for:

- sales
- customers
- repayments
- expenses
- returns
- inventory
- device registration
- generic sync idempotency

The audit found no canonical backend primitives matching the desired operations for:

- income
- cash-drawer shifts
- location writes

These need explicit backend contracts if those entities are intended to sync through the canonical cloud path.

Do not route them through legacy APIs just to make the UI appear synchronized.

## Fulus API target contract

Desired cloud API responsibilities include:

- OPTIONS / health
- Bearer authentication
- active business membership resolution
- device authorization
- canonical sync GET/change feed
- canonical sync POST commands

Expected canonical command surface:

```text
sync_operation
sale_create
customer_create
customer_repayment
expense_create
return_create
inventory_adjust
```

The API should require `business_id` and an authorized `x-fulus-device-id` for business-scoped synchronization.

The GET change feed should use:

- business ID
- device authorization
- cursor
- limit
- `sync_changes` ordered by `sequence`

The POST command path should use a stable operation ID and server-side idempotency.

## FulusSyncCoordinator

Current conceptual implementation:

```dart
class FulusSyncCoordinator {
  FulusSyncCoordinator({
    required FulusSyncApi api,
    required SharedPreferences preferences,
    required Future<void> Function(FulusSyncChange change) applyChange,
  }) : _api = api,
       _preferences = preferences,
       _applyChange = applyChange;

  final FulusSyncApi _api;
  final SharedPreferences _preferences;
  final Future<void> Function(FulusSyncChange change) _applyChange;

  static String _cursorKey(String businessId) =>
      'fulus_sync_cursor_$businessId';

  int cursorFor(String businessId) =>
      _preferences.getInt(_cursorKey(businessId)) ?? 0;

  Future<int> pullAndApply({
    required String businessId,
    int batchSize = 100,
  }) async {
    var cursor = cursorFor(businessId);
    while (true) {
      final page = await _api.pullChanges(
        businessId: businessId,
        cursor: cursor,
        limit: batchSize,
      );
      if (page.changes.isEmpty) return cursor;

      for (final change in page.changes) {
        if (change.sequence <= cursor) continue;
        await _applyChange(change);
        cursor = change.sequence;
        await _preferences.setInt(_cursorKey(businessId), cursor);
      }

      if (!page.hasMore) return cursor;
    }
  }

  Future<void> resetCursor(String businessId) =>
      _preferences.remove(_cursorKey(businessId));
}
```

This must be integrated into the actual runtime and paired with a complete canonical `applyChange` implementation.

## P1 requirements

### Explicit dependency scheduling

Current sync dependency behavior is based largely on priority/FIFO plus handler-specific checks. This is not a full dependency graph.

Move toward explicit dependencies such as:

```text
product/category/supplier/location
        ↓
customer
        ↓
sale / repayment / return / stock movement
```

Use operation dependencies rather than relying on priority alone.

### Structured sync errors

Introduce explicit error categories:

```text
NETWORK
TEMPORARY_SERVER
AUTH_EXPIRED
PERMISSION
VALIDATION
CONFLICT
DEPENDENCY_NOT_READY
PERMANENT_NOT_FOUND
```

Retry/attention behavior must be based on these categories, not brittle string matching.

### Consistent idempotency and retry semantics

Every cloud-sync entity should have the same conceptual lifecycle:

```text
local change
  ↓
outbox operation
  ↓
stable operation ID
  ↓
cloud command
  ↓
idempotent server acceptance
  ↓
server result
  ↓
local reconciliation
  ↓
settled
```

A timeout after the server successfully committed must not cause an unsafe duplicate transaction.

### Authoritative Sync Health

Expose at minimum:

- Cloud Connected
- Device Authorized
- Sync Ready
- Last Push
- Last Pull
- Pending count
- Blocked count
- Attention/errors

This should come from the actual sync system rather than disconnected UI heuristics.

## Integration test matrix

Add or complete tests for:

1. fresh signup
2. fresh device restore
3. offline sale → online
4. offline customer → online
5. offline repayment → online
6. offline expense → online
7. offline return → online
8. device A → device B reconciliation
9. token expiry
10. duplicate request
11. timeout after successful transaction
12. app killed during sync
13. app killed during restore

Tests must verify both local state and server-side effects/idempotency where possible.

## Five mandatory cross-checks

### Cross-check 1 — CI / static analysis / tests

- Verify the latest CI run after the two `SyncStatus` import fixes.
- If it fails, inspect the exact failing job/log and fix it.
- Repeat until the authoritative CI pipeline is green.

**Status: NOT YET PASSED at time of this handoff.**

### Cross-check 2 — Transport audit

Search the complete `lib/sync` and relevant repositories/services for legacy cloud write paths.

Confirm that every intended cloud sync write goes through the canonical Fulus Cloud transport.

**Status: NOT YET PASSED.**

### Cross-check 3 — Backend contract/schema audit

Verify the deployed edge-function source/version and production database RPC/table contracts.

Confirm every syncable entity has a real canonical cloud command/read/reconciliation path.

**Status: NOT YET PASSED.**

### Cross-check 4 — Lifecycle/reconciliation audit

Trace:

```text
cold startup
→ auth
→ membership
→ device registration
→ sync enabled
→ Sync Ready
→ push/pull
→ restore
→ initial reconciliation
→ Sync Ready
```

Confirm there are no races, silent cloud failures, or cursor advancement before successful local reconciliation.

**Status: NOT YET PASSED.**

### Cross-check 5 — Failure/idempotency/integration audit

Verify structured errors, retry behavior, dependency blocking, duplicate safety, timeout-after-success behavior, app-kill recovery, and the integration matrix above.

**Status: NOT YET PASSED.**

## Required completion sequence

Do the work in this order:

1. Verify CI after the current test-import fixes.
2. Fix any CI failure.
3. Audit and remove remaining legacy cloud write transports.
4. Establish backend primitives for missing canonical entities: income, cash drawer, locations.
5. Verify the active `fulus-api` deployment preserves all required routes.
6. Wire `FulusSyncCoordinator` into runtime.
7. Implement canonical change-feed reconciliation for all syncable entities.
8. Make restore complete only after initial reconciliation succeeds.
9. Replace silent startup/background cloud catches with observable handling.
10. Implement explicit dependency scheduling.
11. Implement structured sync errors.
12. Unify idempotency/retry semantics.
13. Implement authoritative Sync Health.
14. Complete the integration test matrix.
15. Run the five independent cross-checks.
16. Only when all five pass, trigger the external APK build.
17. Install the APK on a real device and verify the cloud-sync flows.

## Important regression context

The app previously worked well before the recent cloud-sync/readiness changes. When investigating regressions, specifically compare the commits that introduced startup/backup detection, restore lifecycle changes, sync readiness gating, and onboarding refinement. Do not assume the latest change is the cause without inspecting the exact commit diff and runtime path.

A prior user concern was whether startup/backup detection changes could also explain an APK that downloaded from GitHub but failed to unzip/install correctly. Treat that as a separate release/build-pipeline question unless evidence connects it to the application runtime changes.

## Current known readiness-related commits

- `f02cd5e` — `fix: gate sync triggers on cloud readiness`
- `9b2cb6b` — `test: verify sync readiness gating`
- `0bc943c` — `fix: import SyncStatus in offline sale test`
- `32d9e18` — `fix: import SyncStatus in sale sync test`

## Definition of done

The Cloud Sync hardening is complete only when:

- canonical transport is used consistently;
- all intended syncable entities have cloud command + pull/reconciliation paths;
- backend contracts are real and verified against production;
- startup and restore lifecycle is race-safe and observable;
- dependency scheduling is explicit;
- sync failures are structured and actionable;
- idempotency/retry semantics are consistent;
- Sync Health is authoritative;
- integration tests cover the critical offline/online/multi-device/failure cases;
- **all five cross-checks pass**;
- a release APK is built through the intended workflow;
- the installed APK is tested on a real device.

Until then, the work is **in progress**.
