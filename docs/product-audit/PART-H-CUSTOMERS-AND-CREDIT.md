# Part H — Customers and Credit

**Status:** Source fixes implemented; focused mobile verification and disposable Supabase workflow #875 passed; device/runtime evidence pending  
**Baseline:** `main` at `1383627c58edd8fe4d668951a841444fa94c2642`
**Working branch:** `codex/part-h-customers-credit`
**Audit date:** 2026-11-20
**Environment:** Windows PowerShell; Flutter 3.44.9; no Docker or Supabase CLI available locally. No production Supabase data was read or changed in this Part H pass.

## Scope and trace

Part H covers customer profiles and archive/restore, customer credit sales and repayment, ledger history and balance math, canonical reconciliation, outbox/retry behavior, and business/location authorization. The reviewed path is:

`customer profile/form or checkout → customer/credit repository → Drift transaction → durable sync queue → Fulus API operation → Supabase mutation and authorization → canonical row/change → local reconciler → customer/ledger UI`.

The local credit repository writes balance changes and ledger rows transactionally. Repayments enqueue their durable operation in the same transaction. Cloud repayment is protected by the idempotent `fulus_api_record_customer_repayment` wrapper, `credit.manage`, active-device checks, and server-derived `require_location_access` authorization. Canonical ledger reconciliation reuses the local pending repayment or refund projection when the matching cloud event arrives, avoiding a duplicate visible row. The focused suites cover outbox rollback, overpayment capping/excess, location-scoped history, retry/canonical attachment, and credit-reversal normalization.

Archive preserves the customer and credit history. The profile remains accessible from the archived-customer screen, and the archive confirmation says its history is retained. The previously exposed repayment action could not complete because local and cloud mutations both required an active customer. That mismatch is fixed below without restoring the archived customer.

## Findings and dispositions

### H-001 — Archived customers could not repay retained credit

**Severity:** Medium
**Status:** Fixed in source; local and disposable migration-chain regressions pass.

The profile exposed “Record repayment” for archived records, while the local credit repository and cloud `record_customer_repayment` mutation rejected inactive customers. An archived business customer could therefore retain a debt that the app appeared to let staff collect but could not record.

Repayment and credit-refund adjustments now accept archived customer rows while new credit sales continue to require an active customer. The server migration removes only the active flag predicate from the repayment row lock; business permission, operation idempotency, active-device checks, and the API wrapper’s server-derived location authorization remain in place. Both local and SQL regressions assert that a repayment changes the balance and ledger while preserving archived status.

### H-002 — Canonical customer snapshots dropped the credit limit

**Severity:** Medium
**Status:** Fixed in source; focused local persistence and canonical DTO tests pass.

The database and sync handler store/send `credit_limit`, but the canonical response DTO and repository reconciliation omitted it. A remote customer update could leave another device with an old value. The field now decodes when present and reconciles to local state; legacy snapshots that omit it remain compatible and preserve an existing value. Regression coverage verifies DTO forwarding and repository persistence without enqueuing another write.

The limit remains advisory and is not enforced as a hard credit-sale block. The customer form still does not provide a credit-limit editor; this is documented product scope rather than a hidden sync capability.

### H-003 — Duplicate-customer warnings were persisted but not shown

**Severity:** Low
**Status:** Display added in source; widget/device verification pending.

Sync persisted the server’s `duplicate_warning` on the customer, but the customer profile did not surface it. The profile now displays the advisory text when present. Automated widget coverage and confirmation of when a sync-completed warning becomes visible in an already-open profile remain outstanding.

## Automated evidence

Exact commands:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' run build_runner build
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\flutter.bat' test test/repository/customer_credit_repository_test.dart test/repository/customer_repository_test.dart test/sync/fulus_customer_canonical_reconciler_test.dart test/remote/fulus_customer_ledger_canonical_reconciler_test.dart test/sync/customer_sync_handler_test.dart
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' analyze lib/data/repositories/customer_credit_repository_impl.dart lib/data/repositories/customer_repository_impl.dart lib/data/remote/fulus_customer_canonical_reconciler.dart lib/domain/entities/customer.dart lib/domain/repositories/customer_repository.dart lib/features/money/presentation/screens/customer_profile_screen.dart test/repository/customer_credit_repository_test.dart test/repository/customer_repository_test.dart test/sync/fulus_customer_canonical_reconciler_test.dart
```

The focused test command passed **42 tests, 0 failures, 0 skips**. Targeted Dart analysis reported no issues. Build runner completed successfully; it updated generated code locally. Dependency resolution also changed `pubspec.lock`, which was restored and excluded from the Part H commit. The first test attempt ran before code generation had completed and failed to load generated Drift files; a later combined attempt also used one nonexistent test path and exposed the legacy nullable-money case. Those were corrected; the final exact suite above passed.

For commit `ae4da312462932ab0a5d47e5166b5641b1542b7b`, Fulus Mobile CI **#5094** passed static analysis and **1,114 Flutter tests with 1 skipped**. Its live sync, debug/release APK, and multi-device jobs were skipped by the workflow, so that run provides no device or live-backend behavior evidence.

The SQL regression is added to `supabase/tests/customer_repayment.sql`. Fulus Supabase Migration Chain workflow **#875 passed** from a clean schema, including this customer repayment contract and the repository’s security invariant checks. Docker and the Supabase CLI are absent in this Windows environment, so this evidence came from GitHub’s disposable CI environment. Production Supabase and real business accounts were not used for mutation testing.

## Evidence gaps and next actions

- Recheck Fulus Mobile CI and the migration chain against the final PR head after any follow-up commit.
- Add widget coverage for the duplicate-warning callout and verify the warning refresh behavior after sync.
- Walk through add/edit/archive/restore, credit sale, repayment, overpayment, and credit return on the TECNO KI5k using a designated synthetic QA business.
- Exercise offline repayment → process restart → reconnect → one canonical balance and ledger event, plus concurrent repayments from two devices.
- Recheck role/location denial and customer data isolation with synthetic staff accounts. Existing source/SQL guards do not replace a runtime authorization test.
- Review the complete customer screen, import/restore paths, search, date boundaries, and privacy/accessibility under device and backend QA. The source review and focused tests are not end-to-end evidence.

No release-readiness conclusion is made from this Part H source and unit-test evidence.
