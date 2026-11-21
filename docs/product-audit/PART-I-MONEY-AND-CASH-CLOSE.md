# Part I — Money and Cash Close

**Status:** Local attribution and supplier-ledger cloud implementation are in source; hosted SQL CI and physical/QA verification remain pending
**Audit date:** 2026-11-21
**Repository:** FulusBuild/Fulus-mobile
**Baseline:** merged `main`, `78f4295551f92a42b54fc5bcc8808b0c0a6564c2` (PR #241)
**Branch:** `codex/part-i-money-cash-close`
**Worktree:** pre-existing untracked `android/app/src/main/java/` and `android/local.properties` preserved.
**Environment:** Windows source review. No device or QA backend mutation performed. No APK built.

## Scope and initial trace

Part I covers manual income, expenses, supplier payments, money history/summary, and the cash drawer open/count/close flow. It intersects Part E for supplier payables, Part F/G for sale and reversal effects, Part H for customer repayments, Part J for reports, and Part M for outbox/canonical sync behavior. Those boundaries do not transfer ownership of I's money aggregation and close semantics.

Initial cash-close path:

`DailyClosingCountScreen → MoneyRepository.closeDrawer/computeExpectedCash → RealMoneyRepository → CashDrawerShiftRepositoryImpl → Drift cash_drawer_shifts + SyncQueue → cash_drawer_shift sync handler/API/RPC → canonical reconciliation → DailyClosingSummaryScreen/PDF`

Initial manual-entry paths:

`AddIncomeScreen/AddExpenseScreen → RealMoneyRepository → IncomeRecordRepositoryImpl/ExpenseRepositoryImpl → local row + outbox transaction → income/expense sync handler → Fulus API operation + Supabase RPC → canonical reconciler → Money history/finance projections`

Supplier payments follow `PaySupplierScreen → LedgerPaymentScreen → SupplierCreditRepositoryImpl.recordPayment → local supplier ledger and balance`. Current source/documentation says this supplier ledger is device-local and has no cloud counterpart; see the open Part E finding E-002. Treat that as an existing cross-part blocker, not a duplicate I finding.

## Findings and dispositions

### I-001 — Cash close omits cash supplier payments from expected drawer cash

**Severity:** Medium
**Status:** Local drawer attribution fixed in source and repository-tested; cross-device ledger durability remains blocked by Part E E-002
**Evidence:** `CashDrawerShiftRepositoryImpl.computeExpectedCash` adds opening float and cash sale payments, then subtracts only cash expense rows. It does not inspect supplier ledger payment rows. Those rows persist `paymentMethod`, and supplier payments also appear in the money transaction feed. `RealMoneyRepository.closeDrawer` includes supplier payments in the summary's combined expense total, but that total is not used by `computeExpectedCash`.

When a supplier payment is paid in cash from the drawer during an open session, expected cash was overstated by that payment. The decision is now explicit: a cash supplier payment recorded while a drawer is open is assigned to that exact session; non-cash payments and cash payments recorded without an open session are not subtracted from a drawer. Each new supplier payment and on-account stock purchase also carries a location. A drawer-linked cash entry's location is derived from the shift and a mismatched location is rejected.

**Fix:** New supplier ledger entries require a valid active location. Cash supplier payments made during an open shift also link the exact drawer; mismatched location/shift pairs are rejected. Schema v28 adds attribution and v29 adds sync metadata and queues only entries whose location is known. Money report queries pass active location through to supplier payment reads. A canonical server ledger, idempotent API operation, sync handler/reconciler, strict wire money handling, and restore support now cover new/location-known entries. The close preview shows cash supplier payments as their own outflow.

**Verification:** Focused Part I suite passed 106 tests before cloud changes. Follow-up tests now cover required-location writes, v28→v29 legacy queue behavior, canonical ledger restore references/money conversion, serializer, and local cash behavior. Disposable SQL contract tests have been added to GitHub migration CI but have not run yet. No production or QA business was mutated. Entries whose historic location remains unknown are not automatically synced and require business-side review.

### I-002 — View Money exposed write actions that server permissions reject

**Severity:** Medium
**Status:** Fixed in source; focused automated checks pass; CI/backend/device verification pending
**Evidence:** The `viewMoney` permission is described in the app as viewing the Money tab and transaction history. However, its route guard previously allowed income/expense forms, supplier payment, and cash close. Client permission serialization mapped only read grants, while the cloud RPCs require `finance.manage` for income/expense writes and `cash.manage` for drawer open/close. The app accepts those writes locally first, so a read-only staff member could produce queued operations later rejected by the server.

**Fix:** Added explicit `manageFinance` and `manageCash` permissions, mapped to existing cloud permission codes, and separated read and write route/UI actions. “View Money” remains read-only. The manager preset includes `manageCash`, consistent with the existing manager cloud role; `manageFinance` remains an explicit owner grant. Existing staff grants were not broadened. Manage grants imply the Money read surface in local permissions and cloud projections.

**Verification:** Focused permission, cloud-restore, employee-projection, and finance/cash suites pass; exact command and totals are below. Static analysis passes. The server permission functions were source-reviewed; no live/QA RPC mutation or CI run for this working tree has occurred.

### I-003 — Close summary called a partial calculation “net”

**Severity:** Low
**Status:** Copy fixed in source; automated UI assertion and device review pending
**Evidence:** `netForDay` is calculated as all sales minus expenses and supplier payments. It excludes manual income and customer repayments, and the supplier payment rows are business-wide under E-002. Calling it “Net for this drawer session” implied a complete drawer/business net that the calculation does not represent.

**Fix:** Summary and PDF now label the value “Sales less recorded outflows” and label its outflow row “Expenses and supplier payments.” Numeric calculations are unchanged. The wording is clearer but the supplier attribution gap remains I-001/E-002.

### I-004 — Soft-deleted cash expenses still reduced expected drawer cash

**Severity:** Medium
**Status:** Fixed in source; repository regression passes
**Evidence:** Expected-cash expense selection filtered by location, cash method, date, and sync status but did not filter `deletedAt`. Expense canonical reconciliation does soft-delete rows. A deleted cash expense could therefore continue to reduce the expected count after its canonical deletion.

**Fix:** Expected-cash selection now excludes soft-deleted expenses, matching the ordinary expense-period query. A repository regression inserts a settled, soft-deleted cash expense and checks that expected cash is unchanged.

### I-005 — Closed drawer summaries could not be reopened for review

**Severity:** Medium
**Status:** History access fixed in source; automated repository coverage and device/restart verification pending
**Evidence:** The close screen sends an in-memory `DailyClosingSummary` as route `extra`; the summary route renders a missing-context screen when opened without that extra. The local shift row is persisted and `watchShiftHistory` exists, but no UI caller for the shift-history stream was found. After leaving the summary or restarting, there is no route to review a prior closing summary. A persisted `cashDifference` and raw shift fields exist, but the by-method sales breakdown is not stored on the shift row.

**Fix:** Added a `Cash drawer history` entry for cash managers and owners, backed by the location-scoped persisted shift stream. It shows opening float, expected cash derived from the persisted closing count and difference, counted cash, over/short, and the closing note. It does not claim to restore the old sales-by-method breakdown, which is not persisted on the shift. Deleted shifts are excluded from the stream.

**Verification:** `cash_drawer_shift_repository_test.dart` verifies history is location-scoped and excludes soft-deleted shifts. The full focused Part I suite now passes **94 tests, 0 failures, 0 skips**. Physical restart and second-device confirmation remain pending.

### Manual income accounting rule — excluded from drawer cash

Decision: manual “Other income” is a business finance entry, not a till receipt, and is excluded from expected drawer cash. It has no payment-method field and may represent non-cash income or an accounting adjustment. Cash received through the register must be recorded as a sale so the drawer has a cash tender record. The Add Income screen now states this rule beside the form.

### Existing cross-part dependency — supplier ledger durability

The canonical implementation for E-002 is now present on this branch and linked from Part E. Do not mark cross-device durability verified until the migration-chain SQL workflow passes and a safe isolated QA scenario confirms sync/restore. Historic entries with unknown location remain deliberately unqueued.

## Source trace and automated verification

The reviewed source path for manual entries is `AddIncomeScreen/AddExpenseScreen → RealMoneyRepositoryImpl → IncomeRecordRepositoryImpl/ExpenseRepositoryImpl → local record + outbox transaction → income/expense sync handler → Fulus API operation → finance RPC → canonical reconciliation → Money projections`. The cash path is `DailyClosingCountScreen → RealMoneyRepositoryImpl → CashDrawerShiftRepositoryImpl → local shift + outbox → cash drawer sync handler → location-authorized RPC → canonical reconciliation`. Amounts are integer minor units locally and serialized through `moneyToWire`; UI major-unit amounts are converted with `moneyFromMajor` before repository calls.

Local create/close writes and outbox insertion are transactional. The close operation cannot sync before the shift-open operation has obtained a server ID. The repository enforces one open shift per location locally, and the current SQL has corresponding server uniqueness/concurrency guards. The sync handler preserves permanent business-rule failures for attention and attempts canonical refresh on close conflicts. These are source conclusions; a live QA rejection/convergence scenario was not run.

Focused automated command after the cloud supplier-ledger follow-up (Flutter 3.44.9, Windows):

```powershell
flutter test test/repository/cash_drawer_shift_repository_test.dart test/repository/supplier_credit_repository_test.dart test/data/local/database/migration_upgrade_test.dart test/unit/real_money_repository_test.dart test/repository/income_record_repository_test.dart test/repository/expense_repository_test.dart test/sync/income_sync_handler_test.dart test/sync/expense_sync_handler_test.dart test/sync/cash_drawer_shift_sync_handler_test.dart test/repository/permission_repository_test.dart test/remote/cloud_restore_importer_test.dart test/remote/cloud_restore_supplier_ledger_clear_test.dart test/data/local/employee_identity_projection_store_test.dart test/domain/permission_defaults_test.dart test/repository/finance_stats_repository_test.dart test/sync/fulus_sync_operation_serializer_test.dart
```

**Result:** 131 passed, 0 failed, 0 skipped. Coverage includes open/close validation and concurrent calls, drawer-linked supplier outflows across locations, history location scoping/deleted-row exclusion, v26→v29 migrations and known-location outbox backfill, canonical supplier-ledger restore enum/money conversion, unknown-location write rejection, attention-needed expenses, deleted-expense exclusion, local persistence/outbox, sync payloads, permission grants/restore/projection, and summary aggregation.

Whole-project analysis: `flutter analyze` — **No issues found** (34.8 seconds).

The checkout lacked generated Drift/JSON sources initially. `dart run build_runner build` generated the sources needed for verification; generated `.g.dart` files and the tool-modified lockfile were removed/restored afterward. No generated code is intended for this Part I change.

## Coverage and verification still required

- Continue checking exact server SQL authorization/idempotency, expense and income canonical deletion/update races, role-specific offline write behavior, and multi-location supplier/payment summaries.
- Inspect signs/units, currency minor-unit conversions, effective dates/timezones, edits and reversals, payment-method normalization, duplicate submission, concurrent close/open, expired session, rejected sync, and process restart.
- Establish exact verification commands/results. Source review is not device, local integration, or backend proof.
- On an isolated QA business, verify cash/non-cash income and expenses, cash/non-cash supplier payments, sales with split tenders, cash count differences, retry/restart/sync, and summary/report agreement. No production financial mutation is authorized by this audit.
- Review permissions and location/business scoping for all covered mutations. Supplier-ledger location ownership remains constrained by E-002.

## Evidence gaps and handoff

No device, Supabase project, production business, or AWS resource was used for this pass. No QA or production financial mutation was performed. This is not a completion or release-readiness claim: E-002 source implementation needs hosted SQL CI and isolated QA sync/restore evidence; legacy locationless history needs review if present; I-005 needs physical restart and second-device confirmation.

**Next action:** run the new migration-chain SQL contract in CI, then verify cross-device cash payment followed by drawer close and restore on an isolated QA business; perform physical restart/history confirmation when the phone is connected.

## Documentation disposition

- Added this current Part I report; the historical Part 10 financial-ledger audit remains retained as historical evidence.
- Linked the unresolved supplier-payment backend gap to Part E E-002 rather than duplicating it.
- Updated the QA campaign index, documentation status, and deep-code findings ledger to record Part I findings, source fixes, test evidence, and remaining limits.
