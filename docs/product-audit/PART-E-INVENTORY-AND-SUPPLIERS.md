# Part E — Inventory and Suppliers

**Status:** Source fixes and focused local automated checks complete; physical-device and live QA convergence remain open
**Audit date:** 2026-11-19
**Repository:** FulusBuild/Fulus-mobile
**Baseline:** GitHub `main` after Part D merge, `dce7d074d0d41ddd89f06e9be705ebdfdcace32a`; audit source checkout `codex/fix-e2e-restore-boundary` at `2883f3cd54589b7b66197be701c2f3399c237b3f` contains the corresponding merged source tree.
**Runtime:** Flutter 3.44.9 / Dart on Windows; no Android device or QA backend mutation was used.

## Scope and evidence

Reviewed stock in/out/adjustment, per-location stock projection, low-stock providers and movement history, stock repository transactions, sync queue and handler, canonical movement reconciliation, supplier catalog sync, supplier credit/payable ledger, money units, and cloud restore import/export contracts. Historical Part 11 and Part 10 findings were treated as leads and checked against current code and migrations.

The trace is:

`Record Stock screen → StockMovementRepositoryImpl local transaction → ProductStockLevels + StockMovements + SyncQueue → StockMovementSyncHandler → stock movement/absolute adjustment cloud command → authoritative response → ProductRepository.reconcileStockLevel`

Supplier credit follows:

`Stock In / Pay Supplier → local supplier balance + SupplierLedgerEntries transaction → stable supplier_ledger outbox operation → Fulus API idempotency wrapper → Postgres payable ledger + supplier balance projection + sync_changes → canonical reconciliation → restore snapshot / UI / report`

Evidence is source and automated only. No real business inventory, supplier balance, or production records were changed. No physical-device walkthrough or authenticated QA backend mutation was performed.

## Findings

### E-001 — A rejected cloud stock movement leaves the optimistic local quantity unreconciled

**Severity:** High
**Status:** Fixed in source with regression coverage; QA-device convergence remains unverified.

The local repository applies a stock delta or adjustment immediately and commits it with the movement and outbox row. On a stale device, a stock-out can pass the local cached-stock guard but fail the server's authoritative nonnegative-stock check. `SyncEngine` parks a `BusinessRuleFailure` as attention-needed. The stock handler calls `reconcileStockLevel` only after a successful server response; the rejection path does not restore or refresh the local stock projection. The movement remains a local record and the quantity shown by the product/stock views can remain different from the server.

**Invariant:** After a permanently rejected stock write, local displayed quantity and the authoritative quantity must converge, and the rejected operation must remain clearly distinguishable from an accepted movement.

**Fix:** On a permanent `BusinessRuleFailure`, the handler fetches canonical product stock for the operation's location and reconciles using the rejected operation ID. The repository's operation-aware reconciliation preserves later queued local stock mutations. The original rejection still propagates so SyncEngine parks the rejected operation for attention.

**Regression:** `stock_movement_sync_handler_test.dart` simulates an optimistic stock-out rejected by the cloud and verifies canonical quantity is restored while the business-rule rejection still propagates. If canonical fetch/reconcile itself fails, the original rejection is retained but the local projection can remain stale; retry/repair and two-device runtime evidence remain required.

### E-002 — Supplier payable balances and history are device-local

**Severity:** Medium
**Status:** Canonical implementation added on branch `codex/part-i-money-cash-close`; hosted migration-chain SQL test, CI, and QA/device convergence remain pending. Legacy entries with unknown location attribution are deliberately not auto-synced.

The original implementation stored supplier outstanding balances and `SupplierLedgerEntries` only on the device. This pass adds a canonical server ledger, a server-owned `suppliers.outstanding_balance` projection, location-scoped attribution, idempotent operation handling, outbox sync and reconciliation, sync-change feed inclusion, owner and employee snapshot inclusion, and local restore translation for money units and enum names. A supplier write now requires a valid active location. Cash payments can reference only an open drawer at the same location.

The decision for a multi-device business app is to treat supplier payables as business-wide accounting state. Legacy entries with a location inferred from an existing stock movement or drawer are safely attributed by local migration and queued for sync. Entries whose location cannot be established are preserved locally and not queued; assigning them requires an owner to review their real-world location rather than guessing. Whether those entries exist in the target business is not known from this checkout.

**Implementation evidence:** `SupplierCreditRepositoryImpl` persists new entries with required location and enqueues stable operations; `SupplierLedgerSyncHandler` waits for canonical supplier, location, movement, and drawer references; SQL validates finance permission, location access, device identity, cash-shift ownership, positive amount, and idempotency. Restore imports canonical balances and ledger rows using strict decimal money and enum mapping. Focused Flutter tests cover attribution, restore conversion, and v28→v29 migration. `supabase/tests/supplier_ledger.sql` exercises server mutation/replay, balances, drawer attribution, change feed, and restore. This SQL has not yet run; CI must pass before this finding can be marked verified.

### E-003 — Restore did not clear device-local supplier ledger before deleting suppliers

**Severity:** Medium
**Status:** Fixed in source; regression passes.

Full restore clears/replaces supplier rows, but omitted `supplier_ledger_entries` from the local clear order. Since each local ledger entry references a supplier, a device with supplier credit history could fail restore when the importer tried to remove the referenced supplier.

**Fix:** Clear `supplier_ledger_entries` before `suppliers`. These entries cannot be carried over safely because the cloud restore contract does not include them and a restored supplier may be a different local identity.

**Regression:** `cloud_restore_importer_test.dart` now seeds a supplier and payable entry, restores an empty supplier snapshot, and verifies both local rows are cleared.

### E-004 — Stock comments contradicted current local-first behavior

**Severity:** Low
**Status:** Fixed in source.

The stock movement screen comment claimed local quantity changed only after cloud sync; the repository currently updates the stock projection in its local transaction. The validation helper comment also implied no local insufficient-stock guard existed, while the repository does have a guard against the cached quantity. Updated both comments to describe the actual behavior and note the stale-cache policy question.

## Workflow and invariant notes

- Stock in/out deltas and absolute adjustments are sent as distinct cloud operations. The server returns canonical `current_stock`; successful sync replaces the optimistic projection instead of applying the delta twice.
- Local stock writes are transactionally grouped with movement and outbox creation. Stock-in on-account purchases also include product metadata and supplier credit rows in the same local transaction; rollback tests cover invalid credit metadata.
- Local insufficient-stock rejection is tested. The guard reads cached stock; it is not an authoritative cross-device decision.
- The server stock table and adjustment command enforce nonnegative quantities in migrations. Current source tests do not exercise concurrent device stock writes against a running Postgres instance.
- Supplier payment overpayment clamps the outstanding balance at zero while recording the full payment entry and returning an excess amount. Existing tests assert this behavior. Whether the excess should become a supplier prepayment asset or be rejected is an accounting/product decision; no policy change was made.
- Low-stock and out-of-stock lists use the local joined stock projection and product thresholds. Their visual behavior and stale/offline indication were not exercised on Android.
- Transfers are not offered by the current stock entry UI and the cloud stock sync handler explicitly rejects transfer movements.

## Automated evidence

Toolchain: Flutter 3.44.9 on Windows, generated Dart/Drift sources first created locally with `dart run build_runner build --delete-conflicting-outputs` (exit 0; existing Drift duplicate-reference warnings).

Focused command:

```powershell
flutter test --no-pub test/core/onboarding/onboarding_routing_test.dart test/features/stock/add_edit_product_validation_test.dart test/domain/usecases/product_catalog_csv_test.dart test/sync/stock_movement_sync_handler_test.dart test/repository/stock_movement_repository_test.dart test/repository/supplier_credit_repository_test.dart test/sync/supplier_sync_handler_test.dart test/sync/fulus_supplier_canonical_reconciler_test.dart test/remote/cloud_restore_importer_test.dart
```

**Result:** The prior Part E baseline was 53 passed. The expanded follow-up suite covering onboarding, product validation/export, stock rejection reconciliation, inventory, supplier, and restore paths passed 63 tests, 0 failed, 0 skipped. Targeted Dart analysis reported no issues. The first attempt before generating sources failed to compile because generated `.g.dart` files were absent. A first follow-up command also named a nonexistent test file; the corrected suite passed.

Targeted analyzer command:

```powershell
flutter analyze lib/core/onboarding/onboarding_routing.dart lib/features/auth/presentation/screens/auth_gate_screen.dart lib/features/stock/presentation/screens/stock_screen.dart lib/domain/usecases/product_catalog_csv.dart lib/sync/handlers/stock_movement_sync_handler.dart lib/data/remote/cloud_restore_importer.dart test/core/onboarding/onboarding_routing_test.dart test/features/stock/add_edit_product_validation_test.dart test/domain/usecases/product_catalog_csv_test.dart test/sync/stock_movement_sync_handler_test.dart test/remote/cloud_restore_importer_test.dart
```

This suite is local automated evidence; it is not a device or end-to-end cloud test.

## Documentation disposition and remaining work

- Added this current Part E report; retained historical Part 11 and Part 10 evidence, which contains unique context.
- Updated the QA campaign index and documentation status to point to this report.
- No production schema or data changes were made; AWS remains paused.
- Still required: implement the canonical supplier payable ledger; run local Supabase inventory invariants; perform isolated QA two-device concurrency/retry and restore tests; walk through low-stock, movement history, stock-in/out/adjustment, and supplier payments on the Android phone.
