# Fulus Deep Code Audit — Part 11: Inventory & Stock

**Status:** Active / source audit completed for the primary inventory boundary; verification pending  
**Baseline SHA:** 5bfb9618c0057f4991e00c95dcb019d8fdadf14e  
**Audit branch:** audit/deep-code-part-11-inventory-stock  
**Current SHA:** 41d9e14130f81beea84b2e80d670e221b565d495

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
**Status:** Open; cross-cutting transaction-boundary issue  
**Files:** `lib/features/stock/presentation/screens/record_stock_movement_screen.dart`, `lib/data/repositories/stock_movement_repository_impl.dart`, `lib/data/repositories/product_repository_impl.dart`  
**Functions/classes:** `_submit`, `_recordCostAndCredit`, `StockMovementRepositoryImpl._record`

### Observed behavior

A stock-in operation commits its inventory movement, local stock projection, and durable sync queue item inside `StockMovementRepositoryImpl._record`. After that transaction has committed, the screen performs additional stock-in side effects:

1. optional product cost/supplier update
2. optional supplier-credit ledger write.

Those later operations are separate repository calls and therefore separate transactions.

### Expected invariant

A single user action labelled as one stock-in should not leave inventory, product cost/supplier metadata, and supplier-credit state partially committed when one of its required side effects fails.

### Root cause

The orchestration boundary is the screen, while the durable inventory mutation is committed before its stock-in ancillary state is completed.

### Impact

If product update or supplier-credit persistence fails after the stock movement commits, the user can see an error even though stock was already changed and queued. Retrying the same visible action can create a second stock movement. This is a credible duplicate-inventory path caused by partial local success.

### Evidence

Source trace shows `recordStockIn` completes its DB transaction before `_recordCostAndCredit` is called. The latter performs separate repository writes.

### Fix

Do not patch this with compensation stock movements. The safe fix is a shared application/service transaction boundary that commits the stock movement, product metadata update, and local supplier-credit entry together, with one durable outbox boundary.

Ownership should be coordinated with Parts 06, 07, 09 and the supplier/financial audit rather than introducing a speculative cross-repository transaction abstraction inside Part 11.

### Regression test

Required:

- failure of product metadata write rolls back stock movement and queue item
- failure of supplier-credit write rolls back stock movement and queue item
- successful stock-in commits all components exactly once
- retry after injected failure cannot duplicate stock.

### Cross-check

Sale checkout already keeps sale rows, sale items, payments, local stock decrement and its sale outbox entry inside one local transaction. Manual stock-in does not yet have the same composite transaction boundary.

### Verification

Pending coordinated fix and regression coverage.

---

## FINDING P11-002

**Part:** 11 — Inventory & Stock  
**Severity:** High  
**Status:** Fixed in source; CI/migration/runtime verification pending  
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

CI, migration application, and runtime command-path verification pending.

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

- Run targeted inventory tests.
- Run full required Fulus Mobile CI.
- Apply/verify the new migration in the production Supabase project through the normal migration workflow.
- Verify the live command path rejects a non-stock-tracked product.
- Complete P11-001 with a shared transaction boundary.
- Revisit inventory during Parts 14–16 for sync/convergence and concurrent multi-device evidence.
- Revisit background/process-death behavior in Part 17.

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
