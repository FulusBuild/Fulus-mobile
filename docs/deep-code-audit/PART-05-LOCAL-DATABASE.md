# Part 05 — Local Database & Persistence Audit

**Part:** 05 — Local Database & Persistence  
**Baseline SHA:** `7cf4f36ac466a50cf4acd47ead9a593277c55226`  
**Audit branch:** `audit/deep-code-part-05-local-database`  
**Current SHA:** pending

## Scope

Audited the Drift schema, database lifecycle, migration strategy, foreign-key enforcement, uniqueness/index strategy, local financial storage, draft-cart persistence, and representative repository transaction boundaries.

## Structural inventory

Primary database definition:
- `lib/data/local/database/database.dart`
- `lib/data/local/database/tables.dart`
- `lib/data/local/database/tables/employee_tables.dart`
- `lib/data/local/database/tables/permission_tables.dart`

The database registers 36 tables at schema version 16. The schema uses explicit primary keys, a number of real foreign keys, partial unique indexes for active product SKU/barcode, and a database-level `PRAGMA foreign_keys = ON` in `beforeOpen`.

Representative persistence paths inspected:
- draft cart creation/completion
- sales/payment persistence
- stock/location persistence
- employee/location persistence
- cash-drawer shift persistence
- sync queue/runtime lease persistence
- database-wide business-data clearing
- migration upgrade blocks from versions 1 through 16

## Pass A — Structural inventory

### Proven

- `AppDatabase` owns schema creation and upgrade behavior.
- Testing has an explicit `AppDatabase.forTesting` constructor.
- Foreign keys are explicitly enabled per opened connection.
- Child/parent relationships are represented by Drift `references()` for many core tables.
- Product SKU/barcode uniqueness is implemented as partial unique indexes that ignore soft-deleted rows.
- Sale-item lookup has a dedicated index on `sale_local_id`.
- Migration upgrades are incremental rather than dropping the entire business database.
- Local business-data clearing is performed transactionally with children removed before parents.

### Important schema relationships

Confirmed FK relationships include:
- Sessions → Users
- Employees.authUserId → Users
- LeaveRecords.employeeId → Employees
- LeaveRecords.decidedBy → Users
- ProductStockLevels → Products/Locations
- Sales.locationId/cashierUserId → Locations/Users
- SaleItems → Sales/Products
- SalePayments → Sales
- Returns/return items → their parent entities
- DraftCartItems/DraftCartPayments → DraftCarts
- Expenses/Income/StockMovements/TaxRemittances/CashDrawerShifts → Locations
- UserPermissions → Users

Several identifier columns are intentionally plain text rather than FKs and require cross-part review.

## Pass B/C — Function, branch, and constraint audit

### P05-001 — Floating-point monetary persistence

**Severity:** High  
**Status:** Closed in source; runtime upgrade/convergence evidence pending

**Observed behavior**

Core monetary columns are persisted as SQLite `REAL`, including product prices, sale totals/discounts/tax, sale payments, customer/supplier balances, expenses/income, ledger amounts, tax remittances, and cash-drawer amounts.

Examples include:
- `Products.costPrice`
- `Products.sellingPrice`
- `Customers.outstandingBalance`
- `Sales.subtotal`
- `SalePayments.amount`
- `Expenses.amount`
- `IncomeRecords.amount`
- `CustomerLedgerEntries.amount`
- `SupplierLedgerEntries.amount`
- `CashDrawerShifts.openingCash/closingCash/cashDifference`

**Expected invariant**

Fulus financial state must be deterministic and integer-safe. Monetary persistence must not depend on binary floating-point representation.

**Impact**

Even if current calculations round at selected boundaries, a REAL-backed persistence model permits representation and comparison behavior that can produce fractional-cent/naira artifacts, equality surprises, or non-deterministic arithmetic across repeated transformations. This is a schema-wide financial concern, not a cosmetic formatting issue.

**Fix**

Do not perform a partial conversion in Part 05. Part 10 must first inventory every money calculation, API DTO, mapper, repository, sync handler, report, and migration boundary, then define one integer unit and perform a coordinated migration with explicit compatibility/replay evidence.

**Regression evidence required**

Part 10 must add exact-arithmetic tests covering creation, updates, split payments, credit, refunds/reversals, expenses, income, inventory cost, drawer reconciliation, sync round trips, and migration of existing persisted values.

**Cross-check**

This finding was deliberately handed to Part 10 rather than duplicated as an ad-hoc database-only fix.

---

### P05-002 — Draft-cart cardinality is not database-enforced

**Severity:** Medium  
**Status:** Open; remediation requires safe migration strategy

**Observed behavior**

`DraftCarts` documents an invariant of at most one cart per location, but the table has no unique constraint/index on `locationId`. `DraftCartRepositoryImpl.getOrCreateDraftCart` performs a read-then-insert sequence:

1. query for an existing cart;
2. if none exists, construct a new ULID;
3. insert the cart.

**Expected invariant**

There must be at most one active draft cart for a location.

**Impact**

The invariant currently depends on repository sequencing rather than the persistence layer. Concurrent callers, future code paths, restore/import code, or another isolate could create multiple carts for one location. That can produce divergent carts and make the Sell screen resolve different draft IDs.

**Fix**

A database-level uniqueness constraint/index should ultimately enforce the invariant, with an explicit migration policy for devices that already contain duplicate draft carts. The migration must not silently discard cart items, payments, customer selection, discounts, or tax.

Because a safe duplicate-reconciliation policy is not proven yet, no destructive migration was applied in Part 05.

**Regression test required**

Add a persistence-level uniqueness test after the migration design is approved, plus a repository concurrency regression proving two callers cannot establish two active carts.

**Cross-check**

`DraftCartRepositoryImpl.completeSale` already uses a transaction for sale creation + cart clearing, but that transaction does not establish uniqueness of cart creation.

---

### P05-003 — Active cash-drawer shift cardinality is not database-enforced

**Severity:** High  
**Status:** Open; cross-cutting with Part 09/10/16

**Observed behavior**

`CashDrawerShiftRepositoryImpl.openShift` checks `getActiveShift(locationId)` and then inserts a new shift inside a transaction. `CashDrawerShifts` has no partial unique index enforcing one non-deleted, open shift per location.

**Expected invariant**

A location cannot have two simultaneously open cash-drawer shifts.

**Impact**

The application-level check is vulnerable to a concurrent create path unless the database itself serializes the read/check/insert in a way that is proven for every execution context. Duplicate open shifts would corrupt drawer attribution and closing/reconciliation semantics.

**Fix**

Part 10/16 should define and prove the exact invariant and then add a partial unique index such as one enforcing `location_id` uniqueness where `closed_at IS NULL AND deleted_at IS NULL`, together with a safe migration policy for any existing duplicate open shifts.

No destructive repair was applied in Part 05 because closing or merging historical/open shifts automatically would alter financial state.

**Regression test required**

Persistence-level duplicate-open-shift rejection plus repository concurrent-open tests.

---

## Migration audit

### Proven

- Schema version is 16.
- Upgrade blocks are monotonic `from < N` checks, so a single upgrade traverses all required historical additions.
- Existing business data is generally preserved rather than globally recreated.
- The Sessions v1→v2 replacement is intentionally destructive only to session cache state, not business data.
- Constraint-changing migrations use `TableMigration` where SQLite cannot alter a constraint in place.
- New columns are added with nullable/default-compatible definitions.
- Foreign keys are enabled after connection opening.

### Migration weakness noted

The v6 product SKU/barcode index migration catches uniqueness failures and silently skips the index when an upgraded device already contains duplicates. This preserves the device's data but means the intended DB-level uniqueness guarantee is absent on that installation.

This is recorded as a migration robustness concern rather than a new finding because the backend/application paths already provide additional product identity controls, and automatic duplicate repair would require a product-data policy. Part 08 should cross-check this behavior during the catalog audit.

## Pass D — Cross-system traces

### Draft cart → sale

`DraftCartRepositoryImpl.completeSale` reads the draft, items and payments, constructs a `SaleDraft`, then executes sale creation and cart clearing inside one database transaction. This protects against a committed sale plus failed cart clear leaving the same draft available for accidental duplicate completion.

### Local mutation → sync queue

Core syncable rows use local persistence plus durable queue rows. The queue and runtime lease tables are part of the same Drift database and are covered by the broader sync audit in Parts 14/17.

### Business-data clearing

`BusinessSettingsRepositoryImpl.clearLocalBusinessData` uses one transaction and deletes dependent rows before parent rows because foreign keys are enabled. This was cross-checked against the current `references()` declarations.

## Unknowns / runtime evidence gaps

- No dedicated automated upgrade test was found that opens representative v1/v2/... databases and verifies each migration path against real persisted data.
- No Android process-kill test was found that interrupts a schema migration itself.
- Production devices with legacy schema versions were not directly inspected.
- SQLite/Drift behavior under multiple concurrent database writers should be explicitly tested before relying on application-level cardinality checks.

## Definition-of-done status

- [x] File inventory
- [x] Core classes/tables inspected
- [x] Migration chain inspected
- [x] Foreign-key boundaries inspected
- [x] Transaction boundaries inspected in representative persistence paths
- [x] Concrete findings recorded
- [x] Cross-part handoffs recorded
- [ ] Safe remediation for all findings
- [ ] Dedicated migration upgrade fixtures
- [ ] Runtime/production migration evidence
- [ ] Part CI after final audit documentation commit

## Next recommended step

Part 06 — Repository Layer, with explicit cross-checks for the three persistence findings above and all repository methods that create/update/delete rows involved in those invariants.
