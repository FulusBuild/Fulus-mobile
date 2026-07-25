import 'package:drift/drift.dart';

// No `part 'tables.g.dart';` here, deliberately: Drift's default
// (monolithic) codegen generates table row/companion classes into the
// part file of whatever Dart file holds the @DriftDatabase-annotated
// class — that's database.dart -> database.g.dart, not this file.
// A file that only defines plain Table subclasses gets no generated
// part of its own unless Drift's separate "modular" build mode is
// explicitly configured (a build.yaml opt-in, mainly meant for .drift
// SQL files) — not set up in this project. A `part 'tables.g.dart'`
// directive here would request a file build_runner never intends to
// write, which is exactly what caused the CI failure this comment
// replaces.

/// Shared sync-tracking columns every syncable table carries — Architecture
/// Section 3's exact list (local_id, server_id, created_at, updated_at,
/// sync_status, deleted_at), implemented once here as a mixin rather than
/// repeated by hand on every table, which is exactly the kind of copy-paste
/// surface where one table would eventually drift from the others.
///
/// clientReference is deliberately NOT part of this shared mixin — per
/// Architecture Section 3, it exists specifically because the backend's
/// Sale.client_reference column expects it under that exact name, and only
/// tables that actually call a backend endpoint accepting an idempotency
/// key need it. Adding it here unconditionally would imply every table
/// has a matching backend field, which isn't true yet (Architecture
/// Section 7's noted gap: POST /api/customers and POST /api/inventory/products
/// don't accept this field today).
mixin SyncableColumns on Table {
  TextColumn get localId => text()();
  TextColumn get serverId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => textEnum<SyncStatus>()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

/// Sync states — matches the brief's four-state list exactly (Settled /
/// Pending / Syncing / Attention needed), with `settled` as this enum's
/// name for what the brief calls "Settled" and the architecture document
/// calls "synced" — reconciled here to the brief's own wording since this
/// is the user-facing vocabulary Volume 12 of the Bible actually uses.
enum SyncStatus {
  pending,
  syncing,
  settled,
  attentionNeeded,
}

/// The business's physical locations — Architecture Section 7a. A
/// single-location business has exactly one row here, created silently at
/// onboarding with no location UI ever surfacing (Decision 21's
/// precedent) — this table existing is not the same as the location
/// switcher being visible.
/// @DataClassName('LocationRow') — Drift's default naming would
/// generate a row class literally called `Location` (singular of the
/// table class name), colliding with domain/entities/location.dart's
/// own `Location` domain entity the moment a repository file needs to
/// import both — the exact same collision already fixed for
/// Sales/SaleItems above, applied here proactively before any concrete
/// LocationRepositoryImpl exists to actually hit it.
@DataClassName('LocationRow')
class Locations extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 150)();

  @override
  Set<Column> get primaryKey => {localId};
}

/// User session — the currently signed-in user's own record, mirroring
/// the backend's UserOut shape (verified directly against
/// backend/app/schemas/auth.py: id, username, email, full_name, role,
/// is_active) plus the fields needed to know who's currently active
/// on-device, which the backend has no reason to track since it's a
/// purely local concept (one phone, one signed-in user at a time).
///
/// The refresh token itself is NOT a column here — Architecture Section
/// 11 is explicit that it lives in flutter_secure_storage, never the
/// general Drift database, which is not separately encrypted by design.
/// This table only ever holds what's safe to sit in an unencrypted
/// SQLite file: identity and role, not credentials.
class Sessions extends Table {
  TextColumn get userId => text()();
  TextColumn get username => text()();
  TextColumn get email => text()();
  TextColumn get fullName => text()();
  // Stored as text, not textEnum<UserRole>, deliberately: the backend's
  // UserRole enum (admin/manager/staff/cashier — four roles) is a
  // different vocabulary from the Bible's two-role mobile model
  // (Owner/Employee, Architecture Section 6's explicit note on this
  // mapping). Storing the raw backend string here and mapping it to
  // Owner/Employee at the point Section 6 already specifies, rather than
  // baking the mapping into the schema itself, keeps this table an
  // honest mirror of what the backend actually sent.
  TextColumn get backendRole => text()();
  BoolColumn get isActive => boolean()();
  // Which location this session is currently viewing (Architecture
  // Section 7a) — an owner can change this at will via the location
  // switcher; an employee's is fixed at their invite (Volume 3, line 646)
  // and this column is simply never offered as editable UI for them.
  TextColumn get activeLocationId => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}

/// Products — mirrors ProductBase + ProductOut, verified directly against
/// backend/app/schemas/inventory.py. Catalog fields (name, sku, barcode,
/// pricing) are business-wide per Architecture Section 7a's table; stock
/// is per-location, which is why current_stock does NOT live on this
/// table at all — see ProductStockLevels below. Splitting these two
/// concerns into two tables (rather than one Products table with a
/// location_id, which would duplicate every catalog field per location)
/// is the direct implementation of Section 7a's own reasoning: "only the
/// stock count differs per location, joined in at query time rather than
/// duplicating the whole product row per location."
/// @DataClassName('ProductRow') — same collision-avoidance reasoning as
/// Locations above, against domain/entities/product.dart's own Product.
@DataClassName('ProductRow')
class Products extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get sku => text().withLength(min: 1, max: 64)();
  TextColumn get barcode => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get supplierId => text().nullable()();
  RealColumn get costPrice => real()();
  RealColumn get sellingPrice => real()();
  IntColumn get lowStockThreshold => integer().withDefault(const Constant(10))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Per-location stock — one row per (product, location) pair. This is
/// the table Architecture Section 7a's Transfer feature and Reports'
/// location-first Inventory numbers both read from. currentStock is kept
/// as a plain integer column, deliberately mirroring the backend's own
/// current_stock representation rather than trying to reconstruct it from
/// a locally-summed StockMovements ledger on every read — the backend
/// itself doesn't do that (I verified directly: current_stock is a real
/// column, atomically updated, not derived at query time from the
/// movement history), and there's no reason the mobile mirror should be
/// architected differently from the source it's mirroring.
class ProductStockLevels extends Table {
  TextColumn get productLocalId => text().references(Products, #localId)();
  TextColumn get locationLocalId => text().references(Locations, #localId)();
  IntColumn get currentStock => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => textEnum<SyncStatus>()();

  @override
  Set<Column> get primaryKey => {productLocalId, locationLocalId};
}

/// Customers — business-wide, per Architecture Section 7a's explicit
/// carve-out ("a customer's identity, credit balance, and purchase
/// history belong to the whole business, not to whichever shop happened
/// to serve them first"). No locationId column on this table at all —
/// its absence here is as deliberate as its presence on Sales below.
/// @DataClassName('CustomerRow') — same collision-avoidance reasoning
/// as Locations above, against domain/entities/customer.dart's own
/// Customer.
@DataClassName('CustomerRow')
class Customers extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  RealColumn get outstandingBalance => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Sales — mirrors SaleOut, verified directly against
/// backend/app/schemas/sale.py. clientReference is set equal to localId
/// at creation time (Architecture Section 3's exact reasoning: this is
/// what makes a retried sync submission safe rather than a duplicate).
/// locationId is required, per Section 7a's table — even a single-
/// location business's sales carry the (silently-resolved, never
/// user-facing) one location that exists.
///
/// @DataClassName('SaleRow'): Drift's default naming would generate a
/// row class literally called `Sale` (singular of the table class name)
/// — which collides with domain/entities/sale.dart's own `Sale`, the
/// actual domain entity every repository/UI layer works with. Renaming
/// only the generated class avoids that collision at the one place
/// (data/repositories/) that needs to import both.
@DataClassName('SaleRow')
class Sales extends Table with SyncableColumns {
  TextColumn get clientReference => text()();
  TextColumn get invoiceNumber => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get locationId => text().references(Locations, #localId)();
  DateTimeColumn get saleDate => dateTime()();
  RealColumn get subtotal => real()();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real()();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  // balanceDue and paymentStatus are NOT stored columns — both are
  // derived (total - amountPaid; a simple bucketed comparison) rather
  // than persisted, mirroring the backend's own SaleOut, where
  // balance_due is computed, not a real column (verified directly:
  // Sale.balance_due is a Python @property in the backend model, not a
  // mapped_column). Storing a derived value locally risks it silently
  // drifting out of sync with its own inputs after an edit; computing it
  // at read time in the repository (Architecture Section 4) cannot drift.
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Sale line items — mirrors SaleItemOut exactly, including
/// costPriceAtSale, which the backend snapshots at sale time specifically
/// so historical profit reporting stays accurate even if a product's
/// cost_price changes later (verified directly in the backend's own
/// finance_service.py comment on this exact point). Mobile mirrors that
/// same snapshot discipline rather than reading the product's CURRENT
/// cost at report time, which would silently misreport historical profit.
///
/// @DataClassName('SaleItemRow') — same reasoning as Sales above:
/// avoids colliding with domain/entities/sale.dart's own `SaleItem`.
@DataClassName('SaleItemRow')
class SaleItems extends Table {
  TextColumn get localId => text()();
  TextColumn get saleLocalId => text().references(Sales, #localId)();
  TextColumn get productLocalId => text().references(Products, #localId)();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get costPriceAtSale => real()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Stock movements — the append-only ledger, mirroring the backend's own
/// StockMovement model directly. Never updated once written, only
/// inserted — matching the backend's own append-only design, which I
/// verified directly during the desktop audit and confirmed is
/// deliberate (a compensating "in" movement is added to reverse
/// something, the original row is never mutated).
///
/// quantity and newQuantity are BOTH nullable, and mutually exclusive
/// depending on movementType — this mirrors a genuine backend API split,
/// not an arbitrary local choice: verified directly (twice, against two
/// separate backend snapshots during this same redesign), /stock-in and
/// /stock-out both take a `quantity` delta (StockInRequest/
/// StockOutRequest), while /adjust-stock takes a `new_quantity` absolute
/// target instead (StockAdjustmentRequest) and computes its own delta
/// server-side (inventory_service.adjust_stock: `delta = new_quantity -
/// product.current_stock`). quantity is set for stockIn/stockOut,
/// newQuantity is set for adjustment; the other is always null for that
/// row. Deliberately NOT collapsed into one column: doing so would mean
/// either fabricating a delta this device doesn't actually know (for an
/// adjustment, before syncing, it cannot reliably know the server's
/// current authoritative stock, especially after being offline for a
/// while) or overloading one column with two different meanings that
/// can't be told apart without also checking movementType.
///
/// toLocationId, previously present here, has been removed entirely: it
/// modeled a "transfer" movement type that this table's own prior
/// comment claimed existed, but grepping the entire backend (models,
/// schemas, services, routers) turns up zero mentions of a transfer
/// movement type anywhere — verified directly against two separate
/// backend snapshots during this redesign, not assumed from the earlier
/// claim. There is no write path that could ever populate this column
/// with anything meaningful; a schema column with no possible real data
/// is worse than removing it now and re-adding it properly (with its
/// own real migration) if/when a genuine transfer feature is ever built
/// server-side. Safe to do as a direct edit rather than a migration
/// step: database.dart's schemaVersion is still 1, with onCreate as the
/// only strategy that's ever actually run — there is no released
/// version-1 data anywhere yet for a column removal to silently corrupt.
/// @DataClassName('StockMovementRow') — same collision-avoidance
/// reasoning as Locations above, against
/// domain/entities/stock_movement.dart's own StockMovement.
@DataClassName('StockMovementRow')
class StockMovements extends Table with SyncableColumns {
  TextColumn get productLocalId => text().references(Products, #localId)();
  TextColumn get locationId => text().references(Locations, #localId)();
  TextColumn get movementType => text()(); // in | out | adjustment | sale
  IntColumn get quantity => integer().nullable()();
  IntColumn get newQuantity => integer().nullable()();
  TextColumn get reason => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Expenses and income — per Architecture Section 7a's confirmed answer,
/// locationId is required here too, the same as Sales, not nullable.
/// @DataClassName('ExpenseRow') — same collision-avoidance reasoning as
/// Locations above, against domain/entities/expense.dart's own Expense.
@DataClassName('ExpenseRow')
class Expenses extends Table with SyncableColumns {
  /// Nullable — a real discrepancy discovered while designing the sync
  /// handler: backend/app/models/finance.py's Expense has NO location_id
  /// column at all, verified directly. This table originally had it as
  /// required, under the same (incorrect, for this entity) assumption
  /// Section 7a's location-scoping rule applies uniformly to every
  /// business-write entity. Kept as an optional, LOCAL-ONLY organizational
  /// tag — still useful for on-device filtering ("expenses at this
  /// location") — rather than removed outright, but it is never sent to
  /// or received from the backend (ExpenseCreate/ExpenseOut have no such
  /// field either).
  TextColumn get locationId => text().nullable().references(Locations, #localId)();
  TextColumn get categoryId => text().nullable()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  DateTimeColumn get expenseDate => dateTime()();
  TextColumn get paymentMethod => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// @DataClassName('IncomeRecordRow') — same collision-avoidance
/// reasoning as Locations above, against
/// domain/entities/income_record.dart's own IncomeRecord.
@DataClassName('IncomeRecordRow')
class IncomeRecords extends Table with SyncableColumns {
  /// Nullable — same discrepancy as Expenses.locationId above:
  /// backend/app/models/finance.py's Income has no location_id column
  /// either, verified directly. Same local-only-tag treatment.
  TextColumn get locationId => text().nullable().references(Locations, #localId)();
  TextColumn get source => text()();
  RealColumn get amount => real()();
  DateTimeColumn get incomeDate => dateTime()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The sync queue itself — every pending write across every entity type,
/// one row per queued operation. This is deliberately a single table
/// covering all entity types (rather than a separate queue per table),
/// because the sync engine's priority lanes (Architecture Section 8) need
/// to reason about ordering ACROSS entity types — a sale must outrank a
/// product-photo upload regardless of which table either belongs to, and
/// that comparison is only straightforward if every queued item lives in
/// one place with a shared priority/attempt-count shape.
class SyncQueueItems extends Table {
  TextColumn get id => text()();
  // What kind of operation and which local row it concerns — entityType
  // + entityLocalId together identify the row; operation distinguishes
  // create/update/delete, since the same entity can legitimately be
  // queued for different operations at different times.
  TextColumn get entityType => text()(); // 'sale' | 'product' | 'customer' | ...
  TextColumn get entityLocalId => text()();
  TextColumn get operation => text()(); // 'create' | 'update' | 'delete'
  // priority mirrors Architecture Section 8's three lanes explicitly
  // rather than leaving lane ordering to be re-derived from entityType
  // every time the queue is processed — 0 = sales/payments (highest),
  // 1 = stock/customer/credit, 2 = photos/bulk import (lowest).
  IntColumn get priority => integer()();
  DateTimeColumn get enqueuedAt => dateTime()();
  // syncAttempts is the exact mechanism from Architecture Section 8's
  // head-of-line-blocking fix — a per-item counter that, once it crosses
  // a threshold across separate sync RUNS (not within one run), demotes
  // this specific item to attentionNeeded and lets the queue proceed past
  // it, rather than blocking every item behind it forever. This is the
  // same fix, by the same reasoning, as the one I made directly to the
  // desktop app's offline-sync.ts during the prior audit — carried into
  // mobile's schema from the start rather than left to be rediscovered.
  IntColumn get syncAttempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get lastAttemptedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Settings — a genuinely single-row table locally, mirroring the
/// backend's own BusinessProfile.singleton_guard pattern conceptually
/// (verified directly: the backend enforces exactly one row via a unique
/// constraint on a fixed constant). Drift has no direct equivalent of a
/// CHECK/UNIQUE-on-constant at the table level in the same way, so this
/// is enforced at the repository layer instead (Architecture Section 4:
/// SettingsRepository never exposes an insert path, only
/// getOrCreate()/update(), mirroring the backend's own get_or_create
/// discipline in settings_service.py).
class BusinessSettings extends Table {
  TextColumn get id => text()(); // always the fixed value 'singleton'
  TextColumn get businessName => text()();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();
  BoolColumn get vatEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get vatRate => real().withDefault(const Constant(7.5))();
  TextColumn get receiptFooter => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
