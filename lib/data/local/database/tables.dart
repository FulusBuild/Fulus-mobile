import 'package:drift/drift.dart';

import '../../../domain/entities/app_notification.dart';
import '../../../domain/entities/auth_user.dart';
import '../../../domain/entities/printer_device.dart';

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

/// Local user accounts on this device — the Business Engine's own
/// source of truth for "who can sign in here," per the Architecture
/// Redesign (local Business Engine, no server-issued credentials).
/// Replaces what used to be a thin cache of the backend's users table;
/// this table IS the users table now. Fields mirror backend/app/models/
/// user.py's User columns directly (verified against the actual model:
/// username, email, full_name, hashed_password, role, is_active,
/// failed_login_attempts, locked_until, approval_pin_hash,
/// approval_pin_salt) with two deliberate departures:
///
/// 1. role is a genuine two-value enum (AuthRole.owner/employee — the
///    Bible's actual product vocabulary, Volume 9), not a raw string
///    mirroring the backend's four-value admin/manager/staff/cashier
///    enum. The old Sessions table below stored the raw backend string
///    specifically because the backend was the source of truth for
///    that vocabulary and mobile was just relaying it; now that the
///    Business Engine IS the source of truth, there's no external
///    vocabulary left to honestly mirror, so using the real product
///    model directly is more correct, not a simplification of
///    convenience. Defined in domain/entities/auth_user.dart (a
///    genuine product concept, not a storage detail) and imported here
///    for the column definition — unlike SyncStatus above, which stays
///    data-layer-only because it has no domain-facing meaning of its
///    own beyond sync bookkeeping.
///
/// 2. Deliberately NOT given SyncableColumns, unlike every other table
///    in this file. That mixin exists so a table's rows can be pushed
///    through the generic sync queue like a Product or Sale row —
///    appropriate for business data, actively wrong here:
///    hashedPassword/passwordSalt/approvalPinHash/approvalPinSalt are
///    exactly the values that must never leave this device wholesale
///    through a generic "sync this row" path. A second device gaining
///    a local account for the same business is its own explicit,
///    validated flow (invite/claim, Volume 9) — not "this table's rows
///    get replicated," which SyncableColumns would otherwise imply.
@DataClassName('UserRow')
class Users extends Table {
  TextColumn get localId => text()();
  TextColumn get username => text().withLength(min: 1, max: 150)();
  TextColumn get email => text().withLength(min: 1, max: 255)();
  TextColumn get fullName => text().withLength(min: 1, max: 150)();
  TextColumn get hashedPassword => text()();
  TextColumn get passwordSalt => text()();
  TextColumn get role => textEnum<AuthRole>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // Mirrors auth_service.py's MAX_FAILED_LOGIN_ATTEMPTS/
  // LOGIN_LOCKOUT_DURATION mechanism exactly — verified directly, not
  // assumed — now enforced by the local Business Engine's own login
  // check instead of the backend's.
  IntColumn get failedLoginAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  // Nullable: an owner sets this during their own account setup (Volume
  // 9), not necessarily at the moment the account is first created —
  // matches the backend column's own nullability.
  TextColumn get approvalPinHash => text().nullable()();
  TextColumn get approvalPinSalt => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Which local user is currently signed in on this device, and which
/// location they're viewing. Genuinely local concepts even under the
/// old backend-mirroring design (the backend had no reason to track
/// either), and even more clearly so now that Users above is this
/// device's own source of truth rather than a cache of what a server
/// last reported — everything this table used to cache redundantly
/// (username, email, fullName, backendRole, isActive) now lives
/// authoritatively on the Users row itself; this table only needs to
/// say WHICH Users row that is, not repeat its contents.
///
/// id is a fixed 'current' value, mirroring BusinessSettings' own
/// single-row pattern below, rather than keying on userId as the
/// previous version of this table did — CORRECTED: keying on userId
/// only enforces uniqueness per distinct user, not the actual invariant
/// (Volume 9: a shared device requires a full login each time it
/// changes hands, i.e. genuinely at most one active session, full stop)
/// — it would have silently allowed two different users' "sessions" to
/// coexist as separate rows, which the singular "the currently signed-
/// in user" framing never intended.
///
/// lastSyncedAt is gone entirely, not just renamed: it meant "when did
/// the backend last confirm this session," which has no local-only
/// equivalent — there is nothing external confirming a local session,
/// by design.
class Sessions extends Table {
  TextColumn get id => text()(); // always the fixed value 'current'
  TextColumn get userId => text().references(Users, #localId)();
  // Which location this session is currently viewing (Architecture
  // Section 7a) — an owner can change this at will via the location
  // switcher; an employee's is fixed at their invite (Volume 3, line 646)
  // and this column is simply never offered as editable UI for them.
  TextColumn get activeLocationId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
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

  /// **Bible-only** (Product Design Bible Volume 6, Decision 18:
  /// "Stock tracking is opt-out per product, not mandatory"). No
  /// backend column exists for this today — verified directly against
  /// backend/app/models/inventory.py, same audit pass as everything
  /// else in this file. Added schema-ready ahead of backend support,
  /// the identical precedent StockMovements.toLocationId/
  /// StockMovementType.transfer already set in this same file: a real,
  /// cited product decision the backend hasn't caught up to persisting
  /// yet is not the same claim as a field that shouldn't exist. Defaults
  /// `true`, matching the Bible's own "one product model... as a simple
  /// toggle, defaulting on."
  BoolColumn get tracksStock => boolean().withDefault(const Constant(true))();

  /// **Bible-only** (Volume 6 product table: "Unit... Defaults to
  /// 'piece'"). Display-only, no backend column.
  TextColumn get unit => text().withDefault(const Constant('piece'))();

  /// **Bible-only** (Volume 6: "Photo — Strongly encouraged"). A local
  /// file path, not a URL — no photo-upload endpoint exists in the
  /// backend for products today, so there is nowhere to sync this field
  /// TO yet; it stays device-local until that changes, same status as
  /// every other genuinely-local-only field in this schema.
  TextColumn get photoPath => text().nullable()();

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

  /// **Bible-only** (Product Design Bible Volume 7: "Credit limit — No
  /// [required] — A guide, not an automatic block — see Decision 23").
  /// No backend column — verified directly against
  /// backend/app/models/customer.py, same audit pass as Products'
  /// tracksStock above. Never enforced as a hard block anywhere this
  /// field is read; see CustomerEngine.checkCreditLimitWarning.
  RealColumn get creditLimit => real().nullable()();

  /// **Bible-only** (Volume 7 Loyalty section: "a purchase count per
  /// customer"). No backend column. Incremented locally when a sale
  /// completes for this customer — see CustomerLedgerEntries' own doc
  /// comment for the parallel, and equally real, gap on the sync side of
  /// that same event.
  IntColumn get purchaseCount => integer().withDefault(const Constant(0))();

  /// **Bible-only** (Volume 7: "an optional owner-set threshold, e.g.
  /// every 10th purchase"). Null means loyalty is off for this customer.
  IntColumn get loyaltyThreshold => integer().nullable()();

  /// **Bible-only** (Volume 7: "Photo — No [required] — Helps a cashier
  /// recognize regulars visually"). Same local-file-path, no-upload-
  /// endpoint-yet status as Products.photoPath above.
  TextColumn get photoPath => text().nullable()();

  /// **Not from the Bible or a synced field at all** — this device's
  /// own record of `duplicate_warning` (backend/app/schemas/
  /// customer.py's `CustomerOut.duplicate_warning`), written once by
  /// CustomerRepositoryImpl.markSynced if the create response carried
  /// one, otherwise left null. See CustomerResponseDto's own doc
  /// comment for the full trail: this column is as far as the data
  /// layer takes it — persisted and queryable, but nothing in this pass
  /// builds a UI that actually shows it to anyone. Deliberately not
  /// cleared automatically once "seen" — there's no UI yet to mark it
  /// seen — so a future screen reading this should treat a non-null
  /// value as "flagged at some point," not "flagged just now."
  TextColumn get lastSyncWarning => text().nullable()();

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

  /// **New in schema v4.** Nullable — a sale made while signed in
  /// records who made it; a sale imported from elsewhere, or one made
  /// before this column existed, simply has none, which is a legitimate
  /// state rather than an error (see SaleRepositoryImpl.createSale's own
  /// reasoning for why it's populated best-effort, not required). This
  /// is what lets a receipt show a real cashier name (ReceiptRepositoryImpl)
  /// and CashDrawerShiftRepositoryImpl.computeExpectedCash attribute sales
  /// to the specific shift that rang them up, rather than inferring it
  /// from locationId + a time window alone, which breaks the moment two
  /// shifts at the same location legitimately overlap.
  TextColumn get cashierUserId => text().nullable().references(Users, #localId)();
  DateTimeColumn get saleDate => dateTime()();
  RealColumn get subtotal => real()();

  /// **New in this pass** — the whole-cart discount specifically
  /// (Volume 5: "A single 'Add discount' action... for a whole-cart
  /// discount"), kept separate from `discount` below so either it or a
  /// line's own `lineDiscount` (SaleItems) can change independently
  /// while a cart is being edited without losing track of which is
  /// which. `discount` stays the single number that actually syncs
  /// (`wholeCartDiscount` + every line's `lineDiscount`, combined) —
  /// this column exists purely so that combination can be recomputed
  /// correctly after any one edit, not so two numbers get sent to the
  /// backend where one is expected.
  RealColumn get wholeCartDiscount => real().withDefault(const Constant(0))();
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

/// Sale line items — mirrors SaleItemOut, including costPriceAtSale,
/// which the backend snapshots at sale time specifically so historical
/// profit reporting stays accurate even if a product's cost_price
/// changes later (verified directly in the backend's own
/// finance_service.py comment on this exact point). Mobile mirrors that
/// same snapshot discipline rather than reading the product's CURRENT
/// cost at report time, which would silently misreport historical profit.
///
/// `productLocalId` made nullable in this pass for Quick Sale (Volume 5:
/// "for anything not in the catalog at all... available from Sell at
/// any time"). Real, structural divergence from the backend here, not
/// just a mobile-side addition — checked directly against
/// `backend/app/schemas/sale.py`'s `SaleItemCreate`: `product_id: str`,
/// required, no default. A sale containing a Quick Sale line genuinely
/// cannot sync to this backend as it exists today — see
/// `SaleRepositoryImpl.createSale`'s own doc comment for exactly how
/// that gets handled (marked `attentionNeeded` at creation, not
/// enqueued into a sync attempt that would only ever fail).
///
/// `description` is likewise new — no backend equivalent (`SaleItemOut`
/// has no name/description field; a reader is expected to join through
/// `product_id`). Needed for two reasons: it's the only way a Quick Sale
/// line (no product to join through) can have a name at all, and it
/// keeps a receipt's wording stable even if a real product gets renamed
/// later.
///
/// `lineDiscount` is new too — Volume 5: "Tapping an individual line
/// item reveals a per-item discount." No backend column; folds into
/// `Sales.discount` the same way `Sales.wholeCartDiscount` does.
///
/// @DataClassName('SaleItemRow') — same reasoning as Sales above:
/// avoids colliding with domain/entities/sale.dart's own `SaleItem`.
@DataClassName('SaleItemRow')
class SaleItems extends Table {
  TextColumn get localId => text()();
  TextColumn get saleLocalId => text().references(Sales, #localId)();
  TextColumn get productLocalId => text().nullable().references(Products, #localId)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get costPriceAtSale => real()();
  RealColumn get lineDiscount => real().withDefault(const Constant(0))();

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
/// toLocationId: CORRECTED — an earlier pass through this file removed
/// this column entirely, on the reasoning that no "transfer" movement
/// type exists in the current backend (true) and therefore the concept
/// itself must have been a documentation error (false, and the actual
/// mistake). Reading the primary sources directly settles it:
/// Architecture Section 7a's own table states plainly that StockMovement
/// "Transfer specifically needs two location references (from/to) on
/// the one movement record," and the Product Design Bible's Volume 6,
/// Decision 21 designs Transfer as a real, intended product feature
/// (shown once a second location exists, per the same progressive-
/// disclosure precedent as the location switcher itself) — explicitly
/// sequenced into Phase 2 of the roadmap (Section 14), not Phase 0/1.
/// The correct reading of "no transfer endpoint exists in the backend
/// today" is "not built yet," matching every other Phase-0-ahead-of-
/// Phase-2 schema decision this same architecture makes deliberately
/// (Sale/Expense/Income's locationId columns exist from the first
/// migration for the identical reason) — not "this was a mistake to be
/// scrubbed out." Restored as nullable, populated by nothing today
/// (no write path constructs a transfer movement yet — see
/// StockMovementType.transfer's own doc comment), structurally ready
/// for when Phase 2 actually adds the endpoint and the mobile write
/// path both.
/// @DataClassName('StockMovementRow') — same collision-avoidance
/// reasoning as Locations above, against
/// domain/entities/stock_movement.dart's own StockMovement.
@DataClassName('StockMovementRow')
class StockMovements extends Table with SyncableColumns {
  TextColumn get productLocalId => text().references(Products, #localId)();
  TextColumn get locationId => text().references(Locations, #localId)();
  TextColumn get toLocationId =>
      text().nullable().references(Locations, #localId)();
  TextColumn get movementType => text()(); // in | out | adjustment | transfer | sale
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
  /// Required — CORRECTED. This column, and the corresponding
  /// domain-entity field in expense.dart, were made nullable during an
  /// earlier pass, reasoning that since backend/app/models/finance.py's
  /// Expense has no location_id column, the local field should be
  /// optional too. That reasoning doesn't hold up against Architecture
  /// Section 7a's own table, read directly rather than inferred: "Yes —
  /// confirmed, not inferred... location_id is required, not nullable
  /// ... No hedge toward a nullable 'business-wide expense' case was
  /// built in here." The backend gap changes what's SENT (nothing —
  /// ExpenseCreateDto has no locationId field either, before or after
  /// this fix), not what's required locally — exactly the same split
  /// Sales.locationId already has. Matches that column's non-nullable
  /// convention now.
  TextColumn get locationId => text().references(Locations, #localId)();
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
  /// Required — CORRECTED (again): this column was nullable, on the
  /// same wrong reasoning as Expenses.locationId below ("backend has no
  /// location_id column, so make the local one optional too"). See
  /// income_record.dart's own doc comment for why that's backwards.
  /// Matches Sales.locationId's own non-nullable convention exactly.
  TextColumn get locationId => text().references(Locations, #localId)();
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
/// is enforced at the repository layer instead —
/// BusinessSettingsRepositoryImpl.createBusiness explicitly checks
/// hasBeenConfigured() first and throws rather than allowing a second
/// row (domain/repositories/business_settings_repository.dart).
///
/// STALE COMMENT CORRECTED (Architecture Redesign, Stage 4): this used
/// to say BusinessSettingsRepository "only ever declared
/// watchSettings()/syncFromServer()" — true when written, but the
/// interface has since grown createBusiness/updateSettings/
/// hasBeenConfigured to close a real offline gap (a fresh install
/// couldn't complete "create your business" without a server). Left
/// this note rather than silently deleting the old claim, matching this
/// file's own established practice of marking corrections instead of
/// erasing the reasoning trail.
///
/// address/phone/email/tin added here to close a real, previously-
/// documented gap: the backend's BusinessProfile (app/models/settings.py)
/// has all four (used on printed receipts/invoices per that model's own
/// docstring), and this table didn't, until now.
@DataClassName('BusinessSettingRow')
class BusinessSettings extends Table {
  TextColumn get id => text()(); // always the fixed value 'singleton'
  TextColumn get businessName => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get tin => text().nullable()();
  TextColumn get currencySymbol => text().withDefault(const Constant('₦'))();
  BoolColumn get vatEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get vatRate => real().withDefault(const Constant(7.5))();
  TextColumn get receiptFooter => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local audit trail — mirrors backend/app/models/audit.py's AuditLog
/// table directly (verified against the actual model: user_id, action,
/// module, record_id, details), with one deliberate omission:
/// ip_address/user_agent are dropped entirely, not ported. Both existed
/// to distinguish which of potentially many remote clients made a given
/// HTTP request against a shared server — a genuine backend concept
/// that disappears completely on a single device with no client/server
/// boundary at all (every action already, unambiguously, originates
/// from this same device's own app process, per the Architecture
/// Redesign's own finding on which backend concepts don't survive the
/// move to a standalone app). Porting them anyway as permanently-null
/// columns would be dead weight with no real concept left behind them.
///
/// Given SyncableColumns, unlike Users — this table holds no secrets
/// (unlike a password/PIN hash), and a Host aggregating every till's
/// audit trail into one view is a legitimate, desirable future
/// capability, not a security anti-pattern the way syncing Users' raw
/// credential hashes would be. Append-only by convention (mirroring the
/// backend model's own docstring: "Never updated or deleted") — nothing
/// in this codebase should ever UPDATE or DELETE a row here, only
/// INSERT; updatedAt/deletedAt exist only because SyncableColumns
/// bundles them for every table, and are expected to stay at their
/// initial values for this one specifically.
@DataClassName('AuditLogRow')
class AuditLogs extends Table with SyncableColumns {
  // Nullable: an event can happen with no signed-in user at all (e.g.
  // LOGIN_FAILED for a username that doesn't exist) — matches the
  // backend column's own nullability exactly (verified directly:
  // "nullable for anonymous/system events").
  TextColumn get userId => text().nullable()();
  // e.g. LOGIN | LOGIN_FAILED | LOGIN_BLOCKED_LOCKOUT | LOGOUT |
  // BOOTSTRAP_ADMIN | CREATE | UPDATE | DELETE | STOCK_IN | STOCK_OUT |
  // STOCK_ADJUST | IMPORT | BACKUP_CREATE | BACKUP_RESTORE |
  // PASSWORD_CHANGE | SET_APPROVAL_PIN — the exact vocabulary verified
  // directly against every audit_service.log(...) call site across the
  // whole backend, not a guessed or partial list.
  TextColumn get action => text()();
  // e.g. AUTH | INVENTORY | CUSTOMERS | EMPLOYEES | SALES | FINANCE |
  // BACKUP | IMPORT | POS_SHIFT | POS_RETURN — same source as action.
  TextColumn get module => text()();
  TextColumn get recordId => text().nullable()();
  // JSON-encoded, mirroring the backend's own Text column exactly —
  // verified directly, not assumed to be a structured column type.
  TextColumn get details => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Stage 13 — in-app notification history. A local log of every OS
/// notification NotificationService (core/notifications/) has shown,
/// kept specifically because Volume 12 Decision 43's two notification
/// triggers are interruptive by design (an OS notification the user
/// might dismiss without reading closely) — this table is what a future
/// "Notifications" surface (a bell icon / inbox screen) reads to show
/// the same information again on demand. Not a general-purpose event
/// log for anything else the app does — see AppNotificationType's own
/// doc comment on why this stays deliberately narrow.
///
/// Deliberately NOT a SyncableColumns table: a notification is a
/// purely local, device-specific record of "this device showed this
/// alert once." Nothing about it has a server counterpart to sync
/// toward — a second device the same owner is signed into would
/// generate and show its own stuck-sync notification independently,
/// never receive this device's.
/// @DataClassName('AppNotificationRow') — same collision-avoidance
/// reasoning as Locations above, against
/// domain/entities/app_notification.dart's own AppNotification.
@DataClassName('AppNotificationRow')
class AppNotifications extends Table {
  TextColumn get id => text()(); // ULID
  TextColumn get type => textEnum<AppNotificationType>()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  // Loose, deliberately untyped reference (a Sale's localId today, for
  // blockedPaymentCompleted) — NOT a Drift foreign key. The entity a
  // notification can point at differs per `type` (stuckSync has none at
  // all), and a single nullable FK column can't reference two different
  // tables conditionally. A tap-through UI resolving this into a real
  // navigation target is a future features/ concern, not this table's.
  TextColumn get relatedEntityId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Stage 15 — paired receipt printers. Volume 11 (Settings, Printers):
/// "Pairing, testing, and unpairing a receipt printer, plus setting the
/// default that persists across restarts." A small table rather than a
/// single shared_preferences entry specifically because "the default"
/// implies more than one CAN be paired at once (a business with more
/// than one till, say) even though only one is active by default at a
/// time — a table with an isDefault column models that directly; a
/// single stored value would have to be silently overwritten the moment
/// a second printer was ever paired.
///
/// Deliberately NOT a SyncableColumns table, for the same reason as
/// AppNotifications above: which printer THIS phone is paired with is a
/// hardware fact about this specific device, not business data with a
/// server counterpart. A second phone has its own Bluetooth radio and
/// its own printer pairings entirely.
/// @DataClassName('PairedPrinterRow') — same collision-avoidance
/// reasoning as Locations above, against
/// domain/entities/printer_device.dart's own PairedPrinter.
@DataClassName('PairedPrinterRow')
class PairedPrinters extends Table {
  TextColumn get id => text()(); // ULID, local-only
  TextColumn get name => text()(); // the device's own advertised name
  // Bluetooth MAC address, or the USB device's identifying
  // vendor/product/serial string, depending on `transport` — see
  // domain/entities/printer_device.dart's PrinterDevice.address doc
  // comment for why this isn't split into transport-specific columns.
  TextColumn get address => text()();
  TextColumn get transport => textEnum<PrinterTransport>()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get pairedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A product category — **new in this pass**, filling a real, confirmed
/// gap: the backend has had `/api/inventory/categories` (full CRUD,
/// `inventory_service.list_categories`/`create_category`/
/// `update_category`/`delete_category`, verified directly) all along;
/// nothing on mobile has synced against it until now. Follows Customers'
/// exact push-sync shape below (SyncableColumns, no locationId — a
/// category, like a customer, is business-wide, not per-location) rather
/// than Products' pull-only shape, because unlike Product this genuinely
/// is meant to be creatable from mobile (Volume 6: category management
/// happens whenever a product needs one, is not desktop-exclusive) and
/// the backend endpoint accepts a plain create call with no special
/// idempotency field beyond what CustomerCreateDto already established
/// the pattern for.
/// @DataClassName('CategoryRow') — same collision-avoidance reasoning as
/// every other table in this file, against domain/entities/category.dart.
@DataClassName('CategoryRow')
class Categories extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable().withLength(max: 255)();

  @override
  Set<Column> get primaryKey => {localId};
}

/// A supplier — same "new in this pass, real confirmed backend gap"
/// status as Categories above (`/api/inventory/suppliers`, verified
/// directly against inventory_service.py). Referenced from both Stock In
/// (this table) and, later, Pay Supplier (Finance) — one record, not
/// duplicated per domain.
/// @DataClassName('SupplierRow') — same collision-avoidance reasoning.
@DataClassName('SupplierRow')
class Suppliers extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();

  /// **Bible-only** (Volume 8, Decision 26 — see `SupplierLedgerEntries`'
  /// own doc comment for the full "no backend column at all" gap this
  /// reflects). What the business currently owes this supplier.
  RealColumn get outstandingBalance =>
      real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The Credit Book ledger — **Bible-only** (Volume 7: "a full ledger
/// underneath: every credit sale... that added to it, and every
/// repayment that reduced it"). The backend has no ledger table at all,
/// only the single running `Customer.outstanding_balance` column,
/// adjusted in place server-side by `sale_service._update_customer_balance`
/// — verified directly, same audit as everything above.
///
/// **This table is local-only in a way none of the other additions in
/// this file are — worth being precise about, not glossing over.** A
/// `creditSale`-typed row is written locally purely to give the owner an
/// immediate, honest ledger view the moment a credit sale completes,
/// mirroring what the backend will authoritatively do server-side once
/// that sale syncs — it carries no sync task of its own; it's a local
/// echo of a balance change the Sale row's own sync already accounts
/// for. A `repayment`-typed row tied to a specific sale (`saleLocalId`
/// set) DOES have a real path to the server: PATCH /api/sales/{id}
/// (`sale_service.update_sale`, "only payment fields... can be updated
/// post-creation") — see SaleRepository.recordAdditionalPayment for
/// where that push actually happens; this row is this device's local
/// record of having made that call, not something synced independently.
/// A `repayment` NOT tied to any sale (Volume 7's simpler "amount,
/// method, done" walk-in repayment, freestanding against the customer's
/// whole balance) has **no backend endpoint to reach at all** — grepped
/// the whole backend, confirmed absent — and stays local-only until one
/// exists. `syncStatus` is included on this table for schema consistency
/// with everything else here, but is meaningful (ever leaves `settled`)
/// only for the sale-linked repayment case; a freestanding repayment
/// simply has nowhere to go and is written already-`settled` by
/// convention, not because it actually reached the server.
@DataClassName('CustomerLedgerEntryRow')
class CustomerLedgerEntries extends Table with SyncableColumns {
  TextColumn get customerLocalId => text().references(Customers, #localId)();
  TextColumn get entryType => text()(); // creditSale | repayment | refundAdjustment
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get saleLocalId =>
      text().nullable().references(Sales, #localId)();

  @override
  Set<Column> get primaryKey => {localId};
}

/// **New in this pass** — Volume 5's split-payment support ("A sale can
/// split across more than one method — each amount entered reduces a
/// visible 'remaining' figure"). No backend equivalent at all: `Sale.
/// payment_method` is a single nullable string, `Sale.amount_paid` a
/// single aggregate float — checked directly, same audit as everything
/// else in this file. This table is the local breakdown; `Sales.
/// paymentMethod`/`amountPaid` stay the two fields that actually sync,
/// kept as the aggregate of these rows by
/// SaleRepositoryImpl.completeSale — see that method's own doc comment
/// for exactly how a mixed-method sale collapses into one
/// `paymentMethod` string for the backend's benefit. No SyncableColumns
/// — rides with its parent Sale exactly the way SaleItems does, not
/// tracked for sync independently.
class SalePayments extends Table {
  TextColumn get localId => text()();
  TextColumn get saleLocalId => text().references(Sales, #localId)();
  TextColumn get method => text()();
  RealColumn get amount => real()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The real refund/return mechanism — Volume 5's "Refunds & Returns":
/// "full or partial (specific line items)... a distinct workflow against
/// a past sale." Lives in `POST /api/pos/returns` +
/// `/approve`/`/complete` (`pos_service.py`'s `create_return`/
/// `approve_return`/`complete_return`), a genuinely sophisticated,
/// tested piece of server-side logic — weighted-average pricing per
/// product (a product can appear more than once in a sale at different
/// effective prices), and eligibility tracked across every
/// non-rejected prior return against the same sale, not just the most
/// recent one. New in this pass; nothing on mobile called any of this
/// before.
///
/// Backend stores `items` as a JSON blob directly on the `Return` row —
/// its own comment calls this "a deliberate tradeoff... worth a real
/// decision now that the schema has stabilized rather than assumed
/// permanent either way." This schema uses a real child table
/// (`ReturnItems` below) instead, matching every other line-item table
/// here (`SaleItems`) rather than introducing the one JSON-blob column
/// in an otherwise fully-relational local schema.
///
/// `requestedBy`/`approvedBy` (backend: FKs into `users`) are
/// deliberately absent — same "not this module's job" status every
/// other Auth-coupled field in this schema has; the employee/approval
/// system is expected to track who requested/approved on its own side,
/// keyed by this table's `localId`.
///
/// @DataClassName('ReturnRequestRow') — `Return` collides too closely
/// with Dart's own control-flow vocabulary to read well everywhere it'd
/// otherwise appear (`Future<Return> createReturn(...)`); no such
/// collision exists in Python, so the backend's own `Return` name never
/// had a reason to avoid it. `ReturnRequest` is this schema's name for
/// the same thing throughout.
/// **No `clientReference`** — checked directly against
/// `backend/app/schemas/pos.py`'s `ReturnCreate`, which has no such
/// field, unlike Customer/Sale/StockMovement. Same confirmed gap as
/// Categories/Suppliers: a sync retry after a dropped response can
/// create a genuine duplicate return request server-side. Learned to
/// check this per-schema rather than assume it from Customer/Sale's
/// pattern after getting exactly this wrong once already for Categories
/// (see that table's own doc comment).
@DataClassName('ReturnRequestRow')
class ReturnRequests extends Table with SyncableColumns {
  TextColumn get originalSaleLocalId => text().references(Sales, #localId)();
  TextColumn get status => text()(); // pending | approved | rejected | completed
  TextColumn get returnReason => text().withLength(min: 1, max: 500)();
  RealColumn get refundAmount => real()();
  TextColumn get refundMethod => text().withLength(min: 1, max: 30)();
  BoolColumn get inventoryRestored =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// One returned product+quantity within a [ReturnRequests] row — rides
/// with its parent exactly the way `SaleItems` does, no independent sync
/// tracking.
@DataClassName('ReturnItemRow')
class ReturnItems extends Table {
  TextColumn get localId => text()();
  TextColumn get returnLocalId =>
      text().references(ReturnRequests, #localId)();
  TextColumn get productLocalId => text().references(Products, #localId)();
  IntColumn get quantity => integer()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The resumable cart — Volume 5, Decision 14: "the cart persists
/// locally between app sessions, not just between screens." No backend
/// equivalent at all (a `Sale` row only ever represents a *finished*
/// transaction) and, before this pass, no local persistence either —
/// `domain/entities/sale_draft.dart`'s own `SaleDraft` is a plain,
/// non-persisted in-memory value object, explicitly built for "Section
/// 2's cart Cubit — not yet built in this phase." That comment is why
/// these three tables exist: something has to actually survive an app
/// restart for Decision 14 to be true, and nothing did.
///
/// Deliberately entirely separate from `Sales`/`SaleItems`/
/// `SalePayments` rather than a `status` column added to those — this
/// keeps the "Sales = finished, synced transactions" invariant those
/// tables and their sync handler already have completely intact.
/// `SaleRepositoryImpl.completeSale` reads a `DraftCarts` row + its
/// items/payments, builds the existing `SaleDraft` value object from
/// them, and calls the existing `SaleRepository.createSale` — nothing
/// about how a finished sale gets created or synced changes.
///
/// No `SyncableColumns` on any of these three — an in-progress cart
/// never needs to sync; only the finished sale it eventually becomes
/// does. At most one row per `locationId` (enforced by
/// `DraftCartRepositoryImpl.getOrCreateDraftCart` always looking for an
/// existing one first, the same way `ProductStockLevels`'
/// (product, location) uniqueness is enforced by convention rather than
/// a database constraint elsewhere in this schema).
@DataClassName('DraftCartRow')
class DraftCarts extends Table {
  TextColumn get localId => text()();
  TextColumn get locationId => text().references(Locations, #localId)();
  TextColumn get customerLocalId => text().nullable()();
  RealColumn get wholeCartDiscount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

@DataClassName('DraftCartItemRow')
class DraftCartItems extends Table {
  TextColumn get localId => text()();
  TextColumn get draftCartLocalId => text().references(DraftCarts, #localId)();
  TextColumn get productLocalId => text().nullable().references(Products, #localId)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get costPriceAtSale => real().withDefault(const Constant(0))();
  RealColumn get lineDiscount => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {localId};
}

@DataClassName('DraftCartPaymentRow')
class DraftCartPayments extends Table {
  TextColumn get localId => text()();
  TextColumn get draftCartLocalId => text().references(DraftCarts, #localId)();
  TextColumn get method => text()();
  RealColumn get amount => real()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// **No `clientReference`** — checked directly against
/// `backend/app/schemas/finance.py`'s `ExpenseCategoryCreate`, a bare
/// `name` field with no idempotency key, same confirmed gap as
/// Categories/Suppliers/Returns.
@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table with SyncableColumns {
  TextColumn get name => text().withLength(min: 1, max: 100)();

  @override
  Set<Column> get primaryKey => {localId};
}

/// A supplier's payables balance — Volume 8, Decision 26: "A supplier's
/// balance works exactly like the customer credit book (Volume 7),
/// mirrored... accumulated whenever Stock In records a cost price that
/// wasn't paid on the spot." **100% local-only, more so than the
/// customer credit book was** — checked directly against
/// `backend/app/models/inventory.py`'s `Supplier`: no balance column at
/// all, unlike `Customer.outstanding_balance` which at least exists
/// server-side. There is nothing server-side to reconcile this against
/// today; this table is this device's own record of what the business
/// owes, full stop.
///
/// Same two-entry-type shape `CustomerLedgerEntries` uses
/// (`stockPurchaseOnCredit` mirrors `creditSale`; `paymentMade` mirrors
/// `repayment`), same reasoning: one ledger, one running balance,
/// combined into `Suppliers.outstandingBalance` (a column added
/// alongside this table — see that column's own doc comment in the
/// `Suppliers` class above).
@DataClassName('SupplierLedgerEntryRow')
class SupplierLedgerEntries extends Table {
  TextColumn get localId => text()();
  TextColumn get supplierLocalId => text().references(Suppliers, #localId)();
  TextColumn get entryType => text()(); // stockPurchaseOnCredit | paymentMade
  RealColumn get amount => real()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get stockMovementLocalId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Volume 8, Taxes: "tax collected, by period... An owner can mark a
/// period as remitted." **100% Bible-only** — grepped the whole backend
/// for any tax-tracking model or service function; none exists beyond
/// the flat `Sale.tax`/`BusinessSettings.vatRate` columns already in
/// this schema. This table is purely local record-keeping of which
/// periods an owner has already dealt with — "the app tracks what's
/// owed; it does not file anything" (Decision 28) applies just as much
/// to this table's own scope as to the product's.
@DataClassName('TaxRemittanceRow')
class TaxRemittances extends Table {
  TextColumn get localId => text()();
  TextColumn get locationId => text().references(Locations, #localId)();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  RealColumn get amountRemitted => real()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get remittedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// The Cash Drawer & Daily Closing — Volume 8: "Open Shop... asks...
/// how much cash is in the drawer to start the day," and Daily Closing's
/// four-step reconciliation flow. Mirrors the backend's own `Shift`
/// model closely (`backend/app/models/pos.py`, verified directly) —
/// this is genuinely synced, not local-only, since the backend already
/// has `POST /api/pos/shifts` / `.../close` and a real `cashier_id` FK
/// into `users` that this schema can now actually reference (Users
/// exists in this merged base; it didn't when this stage's own earlier
/// pass first considered and deferred Shift, for exactly that reason).
///
/// `closingSummaryLocked` is this table's one addition beyond what the
/// backend tracks directly — Decision 29: "sales for that day lock from
/// further editing" once Daily Closing completes. The backend doesn't
/// need its own column for this (it can derive "is today locked" from
/// "does a completed Shift exist covering this date" at query time);
/// mobile keeps it as an explicit flag purely so a screen can check it
/// with a plain read instead of a computed join every time it renders.
/// **No `clientReference`** — checked directly against
/// `backend/app/schemas/pos.py`'s `ShiftOpen`, which has no such field.
/// Same confirmed gap as Categories/Suppliers/Returns/ExpenseCategories
/// — a sync retry after a dropped response could open a genuine
/// duplicate shift server-side. In practice this risk is smaller here
/// than for the others: `pos_service.open_shift` almost certainly
/// rejects opening a second shift while one is already active for the
/// same cashier (not verified line-by-line — a reasonable inference
/// from `get_active_shift` existing as a dedicated "is there one
/// already" endpoint — but not a substitute for the backend actually
/// having an idempotency key).
@DataClassName('CashDrawerShiftRow')
class CashDrawerShifts extends Table with SyncableColumns {
  TextColumn get cashierUserId => text()();
  TextColumn get locationId => text().references(Locations, #localId)();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  RealColumn get openingCash => real().withDefault(const Constant(0))();
  RealColumn get closingCash => real().nullable()();
  RealColumn get cashDifference => real().nullable()();
  TextColumn get closingNote => text().nullable()();
  BoolColumn get closingSummaryLocked =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {localId};
}
