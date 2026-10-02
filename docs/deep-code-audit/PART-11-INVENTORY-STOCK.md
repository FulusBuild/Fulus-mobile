# Fulus Deep Code Audit — Part 11: Inventory & Stock

**Status:** Complete for the audited inventory boundary; P11-001 and P11-002 source fixes verified by CI  
**Baseline SHA:** 5bfb9618c0057f4991e00c95dcb019d8fdadf14e  
**Audit branch:** audit/deep-code-part-11-inventory-stock  
**Current SHA:** 83377dae947d8e265bd79922eaa51ee7f7942a21

## Scope

Inventory and stock were traced across:

- local stock movement validation and domain entities
- local Drift stock levels and movement persistence
- product stock projections
- sale-side local stock decrement
- return-side stock restoration workflow
- stock sync handler and queue identity
- canonical stock-movement reconciliation
- restore snapshot inventory contracts
- Supabase inventory tables, constraints, indexes and RLS
- authoritative inventory RPCs and idempotency
- live production inventory invariants

## Structural inventory

Primary source files inspected:

- `lib/core/business_engine/stock_movement_validation.dart`
- `lib/domain/entities/stock_movement.dart`
- `lib/domain/entities/product_stock_snapshot.dart`
- `lib/domain/repositories/stock_movement_repository.dart`
- `lib/data/repositories/stock_movement_mapper.dart`
- `lib/data/repositories/stock_movement_repository_impl.dart`
- `lib/data/remote/endpoints/stock_movements_api.dart`
- `lib/data/remote/fulus_stock_movement_canonical_reconciler.dart`
- `lib/sync/handlers/stock_movement_sync_handler.dart`
- `lib/data/repositories/product_repository_impl.dart`
- `lib/data/repositories/sale_repository_impl.dart`
- `lib/data/repositories/return_repository_impl.dart`
- `lib/features/stock/application/stock_providers.dart`
- `lib/features/stock/presentation/screens/stock_screen.dart`
- `lib/features/stock/presentation/screens/product_detail_screen.dart`
- `lib/features/stock/presentation/screens/record_stock_movement_screen.dart`
- `test/core/business_engine/stock_movement_validation_test.dart`
- `test/repository/stock_movement_repository_test.dart`
- `test/sync/stock_movement_sync_handler_test.dart`

Inventory-related migration history inspected:

- `202609221200_phase_2_stock_adjustment_sync.sql`
- `202609221330_lock_stock_row_for_absolute_adjustment.sql`
- `202609221410_fix_absolute_stock_adjustment_atomic_target.sql`
- `202609221500_inventory_command_idempotency.sql`
- `20260922170000_fix_inventory_movement_wire_contract.sql`
- `20260922214500_fix_product_initial_stock_sync.sql`
- `20260922220000_fix_product_initial_stock_sync_v2.sql`
- `20260922231500_emit_sale_return_stock_changes.sql`
- `20260922232500_emit_sale_stock_change.sql`
- `20260923080000_stock_movement_change_timestamp_contract.sql`
- `20260923095500_restore_catalog_initial_stock_scope.sql`
- `20260923161000_harden_finance_payment_inventory_action_wrappers.sql`
- `20260923192000_reassert_catalog_initial_stock_actor_hardening.sql`

## End-to-end trace

### Local stock-in/out/adjustment

`RecordStockMovementScreen._submit`
→ permission/approval checks
→ `StockMovementRepository.recordStockIn/Out/Adjustment`
→ `StockMovementRepositoryImpl._record`
→ local `product_stock_levels` update + `stock_movements` insert
→ durable `stock_movement.create` queue item.

The local write is transactional. Negative resulting stock is rejected before the movement and queue item commit.

### Sale coupling

`SaleRepositoryImpl.createSale` writes the sale, items and payments in one transaction and performs an optimistic local stock decrement for tracked products. The cloud sale path is responsible for authoritative stock movement generation. This is intentionally a separate path from manual stock movements.

### Return coupling

Return eligibility is computed from the original sale and prior non-rejected returns. The return workflow restores inventory through the return path rather than treating a manual stock movement as the return itself.

### Sync

`StockMovementSyncHandler.sync`
→ validates queue operation type
→ loads the local movement
→ resolves product/location server identities from the persisted movement location
→ submits `stock_movement.create` or `stock_adjustment.create`
→ reconciles the server-returned authoritative stock
→ marks the movement settled with queue-operation stale-response protection.

The active UI location is not used as the movement's location during replay.

### Canonical convergence

`FulusStockMovementCanonicalReconciler`
accepts only `stock_movement` canonical entities, maps the richer movement contract, and persists the canonical movement identity. Product stock levels are reconciled through product stock snapshots and authoritative command responses.

## Database evidence

Live production schema:

- `inventory_movements.business_id`, `product_id`, `location_id`, `quantity_delta`, `operation_id`
- unique `(business_id, operation_id)`
- `product_stock_levels` primary key `(product_id, location_id)`
- `product_stock_levels.current_stock >= 0`
- inventory movement quantity delta cannot be zero
- inventory movement reason must contain non-whitespace text
- both tables have RLS enabled
- direct authenticated writes to the inventory tables are not granted; mutation is through privileged server-side command paths.

The inventory command RPCs validate business membership/device authorization and product/location business ownership. Absolute quantity setting additionally requires `tracks_stock=true`.

## Live production invariant checks

At audit time:

- inventory movements: **1,282**
- product/location stock rows: **236**
- inventory movements with mismatched product/business ownership: **0**
- inventory movements with mismatched location/business ownership: **0**
- stock rows whose product and location belong to different businesses: **0**
- negative stock rows: **0**
- stock-level rows whose current stock differs from the sum of inventory movement deltas for the same product/location: **0**
- inventory movements belonging to products with `tracks_stock=false`: **0**

These are production observations at the audit timestamp, not substitutes for regression/runtime evidence.

## FINDING P11-001

**Part:** 11 — Inventory & Stock  
**Severity:** High  
**Status:** Fixed; required CI green; runtime retry/process-death evidence remains part of later cross-cutting sync audits  
**Files:** `lib/features/stock/presentation/screens/record_stock_movement_screen.dart`, `lib/data/repositories/stock_movement_repository_impl.dart`  
**Functions/classes:** `_submit`, `StockMovementRepositoryImpl._record`

### Observed behavior

Stock In originally committed its inventory movement, local stock projection, and durable sync queue item before optional product cost/supplier metadata and supplier-credit writes completed. Those later writes were separate repository transactions.

### Expected invariant

One Stock In action must not partially commit inventory, product metadata, and supplier-credit state.

### Root cause

The UI was composing multiple repository transaction boundaries.

### Fix

Stock In now enters one Drift transaction at the repository boundary. The same transaction covers:

1. local stock projection
2. stock movement
3. optional product cost/supplier metadata
4. product outbox entry when metadata changes
5. supplier outstanding balance and supplier ledger entry when purchased on account
6. stock-movement outbox entry.

The UI now submits all Stock In inputs through this single operation. No compensating stock movement is used.

### Regression coverage

Added repository coverage proving:

- the composite operation commits stock, movement, product metadata, both required outbox entries, and supplier credit together;
- a missing supplier during an on-account purchase rolls back stock, movement, product metadata, outbox entries, and supplier balance/ledger.

### Verification

Fulus Mobile CI run **3509** completed successfully. Static analysis, the full Flutter test suite, live sync contract test, and multi-device convergence test all passed.

### Cross-check

Sale checkout already uses one local transaction for its sale rows, payments, inventory decrement, credit effect, and outbox. Manual Stock In now has the same atomic local-write property for its own composite state.

## FINDING P11-002

**Part:** 11 — Inventory & Stock  
**Severity:** High  
**Status:** Fixed; CI green; production invariant evidence clean at audit time  
**Files:** `lib/data/repositories/stock_movement_repository_impl.dart`, `lib/features/stock/presentation/screens/product_detail_screen.dart`, `supabase/migrations/20261002200000_enforce_inventory_tracks_stock.sql`, `test/repository/stock_movement_repository_test.dart`  
**Functions/classes:** `StockMovementRepositoryImpl._record`, `ProductDetailScreen`, database inventory movement insert boundary

### Observed behavior

A product with `tracksStock=false` could still reach the manual stock-movement path.

- Product detail displayed **Record stock** regardless of `tracksStock`.
- The local repository created/updated a stock-level row without checking the product's tracking flag.
- The delta inventory command path did not enforce the tracking flag at its database insert boundary.

The absolute-set command already rejected non-stock-tracked products, so the mutation contract was inconsistent.

### Expected invariant

A product explicitly configured as not tracking stock must not accumulate inventory movements or stock levels through manual inventory operations.

### Root cause

The `tracksStock` invariant was enforced in some sale and absolute-adjustment paths but not at the common manual stock-movement boundary.

### Fix

- Local `StockMovementRepositoryImpl._record` now requires the product to exist and `tracksStock=true` before changing stock or inserting the movement.
- Product detail only exposes **Record stock** when the product tracks stock and the user can manage stock.
- A database trigger rejects inventory movement inserts for non-stock-tracked products, closing the privileged-command boundary and protecting future inventory writers.

### Regression test

Added repository coverage proving a non-stock-tracked product cannot create a stock movement or stock-level row.

### Cross-check

Live production data currently contains zero inventory movements for non-stock-tracked products. Existing stock/business/location scope checks also returned zero violations.

### Verification

CI and source verification complete. Live production inventory invariants remain clean; direct privileged command-path rejection is covered by the database trigger and should be revisited during Part 13/20 runtime security verification..

## Pass status

### Pass A — Structural inventory

Complete for the primary inventory boundary.

### Pass B — Function/class audit

Complete for the primary repository, sync, reconciliation, product projection, sale/return coupling and stock UI paths.

### Pass C — Line/branch audit

Complete for the inspected inventory paths. Important branches covered include:

- positive/zero/negative quantities
- absolute target zero
- negative resulting stock
- missing product/location/server identity
- stale queue operation
- newer queued mutation
- sale-derived movements
- unsupported transfer
- non-stock-tracked product
- canonical upsert/delete
- location switching during pending replay.

### Pass D — Cross-system audit

Complete for source-level tracing. Production database invariant queries were also run.

## Remaining verification

- Revisit inventory during Parts 13–16 for cloud API, sync/convergence, and concurrent multi-device evidence.
- Revisit background/process-death behavior in Part 17.
- Revisit financial integer-money interaction in Part 10.

The Part 11 local inventory boundary is otherwise closed.

## Session handoff

**Part:** 11 — Inventory & Stock  
**Baseline SHA:** 5bfb9618c0057f4991e00c95dcb019d8fdadf14e  
**Audit branch:** audit/deep-code-part-11-inventory-stock  
**Current SHA:** 41d9e14130f81beea84b2e80d670e221b565d495

### Completed

- Read the master audit plan and current Part 10 baseline.
- Inventoried the primary inventory implementation.
- Traced local mutation → outbox → cloud command → canonical reconciliation.
- Cross-checked sales, returns, restore and location replay.
- Queried live production inventory invariants.
- Fixed the non-stock-tracked manual movement boundary.
- Added a regression test and migration.

### Findings

- P11-001 High — stock-in ancillary writes are not atomic with the stock movement.
- P11-002 High — non-stock-tracked products could receive manual inventory movements. Fixed in source.

### Next recommended step

Run targeted tests and CI. If green, inspect the migration against the live Supabase schema and then continue P11-001 transaction-boundary design or close Part 11 with that issue explicitly carried into the repository/domain cross-cutting work.
