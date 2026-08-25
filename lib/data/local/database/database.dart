import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/diagnostics/models/diagnostic_enums.dart';
import '../../../domain/entities/app_notification.dart';
import '../../../domain/entities/auth_user.dart';
import '../../../domain/entities/printer_device.dart';
import 'tables.dart';
import 'tables/employee_tables.dart';

part 'database.g.dart';

/// The local database — Architecture Section 3's Drift choice, and the
/// single source of truth on-device per the brief's own stated
/// architecture principle ("the local database is the source of truth").
///
/// MERGE NOTE (integrating Stages 1-4 + 9-12 + 13-17, three sessions that
/// each worked from the bare pre-Stage-1 checkpoint without visibility
/// into each other): schemaVersion is 2, not the 1 any individual
/// session reasoned about in isolation. Stage 13-17's session correctly
/// pointed out this project's first-ever onUpgrade case was needed for
/// its own two tables (AppNotifications, PairedPrinters) — that
/// reasoning turned out to apply more broadly once Stages 1-4's and
/// 9-12's independent table additions (Users, the rebuilt Sessions,
/// AuditLogs, Employees, AttendanceRecords, LeaveRecords) are merged in
/// alongside them: every one of these is new relative to the TRUE
/// original schemaVersion 1 (the bare renamed baseline every session
/// actually started from), so onUpgrade below covers all of them, not
/// just the two Stage 13-17 added.
///
/// SECOND MERGE NOTE (Stages 5-8 landing): schemaVersion is 3, not the 2
/// above. Same situation one level up — Stages 5-8 (Inventory,
/// Customers, Sales/POS, Finance) were built against the true
/// schemaVersion-1 baseline too, in parallel with everything the first
/// merge note describes, with no visibility into it either. Thirteen
/// genuinely new tables (Categories, Suppliers, CustomerLedgerEntries,
/// SalePayments, ReturnRequests, ReturnItems, DraftCarts, DraftCartItems,
/// DraftCartPayments, ExpenseCategories, SupplierLedgerEntries,
/// TaxRemittances, CashDrawerShifts) plus new columns on five tables
/// that already existed at version 1 (Products, Customers, Sales,
/// SaleItems, Suppliers) — see each column's own doc comment in
/// tables.dart for exactly what it is and why, and onUpgrade's own
/// `from < 3` block below for how each gets migrated. All thirteen new
/// tables and every column change belong to this same single delivery
/// (Stages 5-8 built and reconciled together in one working pass, never
/// individually shipped) — one version bump, not one per file edited
/// along the way.
/// THIRD MERGE NOTE (Phase 0 completion pass): schemaVersion is 4, not
/// the 3 above. One new nullable column (Sales.cashierUserId — see its
/// own doc comment in tables.dart for why) and two existing columns
/// (Employees.authUserId, LeaveRecords.decidedBy) gaining a real FK
/// constraint into Users now that Users exists in this schema — both
/// were explicitly left for "whoever merges this against the real auth
/// table" (employee_tables.dart's own prior doc comments), which is
/// this pass.
///
/// FOURTH MERGE NOTE (gap-closure pass — Receipt photo attachment on
/// expenses): schemaVersion is 5. One new nullable column,
/// `Expenses.receiptPhotoPath` — purely additive, same `addColumn`
/// treatment as `Products.photoPath`/`Customers.photoPath` got in the
/// `from < 3` block below, just one version later.
///
/// FIFTH MERGE NOTE (DB-level uniqueness on Products.sku/barcode):
/// schemaVersion is 6. Two partial unique indexes, issued via
/// `customStatement` rather than `Products.uniqueKeys` — Drift's
/// `uniqueKeys` can't express the `WHERE deleted_at IS NULL` clause
/// these need so a soft-deleted product's sku/barcode can be reused by
/// a new one, matching how every other uniqueness check in this app
/// already treats a soft-deleted row as gone. Defense-in-depth
/// alongside the existing application-layer generator
/// (`product_import_engine.dart::_generateSku`), not a replacement for
/// it.
///
/// SIXTH NOTE (Reports & Auditability — void sales): schemaVersion is
/// 7. One new column, `ReturnRequests.isVoid` — purely additive,
/// boolean, defaults false. A void reuses the exact same
/// createReturn/completeReturn mechanics as a customer return (reverse
/// stock, reverse credit if applicable); this column is the only thing
/// that tells the two apart afterward, since conflating them would
/// lose a real business distinction (a void rate reflects cashier
/// error, a return rate reflects product/customer issues) that
/// reporting on this data needs to preserve.
///
/// SEVENTH NOTE (Diagnostic & Crash Logging System): schemaVersion is
/// 8. One new table, `DiagnosticEvents` — purely additive, same
/// createTable treatment every other new-table version bump above got.
/// Not a SyncableColumns table (see that table's own doc comment in
/// tables.dart); nothing about this addition touches or migrates any
/// existing table's data.
@DriftDatabase(
  tables: [
    Locations,
    Users,
    Sessions,
    Products,
    ProductStockLevels,
    Categories,
    Suppliers,
    Customers,
    CustomerLedgerEntries,
    Sales,
    SaleItems,
    SalePayments,
    ReturnRequests,
    ReturnItems,
    DraftCarts,
    DraftCartItems,
    DraftCartPayments,
    StockMovements,
    ExpenseCategories,
    Expenses,
    IncomeRecords,
    SupplierLedgerEntries,
    TaxRemittances,
    CashDrawerShifts,
    SyncQueueItems,
    BusinessSettings,
    AuditLogs,
    // Stage 11 (Employees) — see tables/employee_tables.dart's own doc
    // comment for why these deliberately don't use SyncableColumns.
    Employees,
    AttendanceRecords,
    LeaveRecords,
    // Stage 13 / Stage 15 — see tables.dart's own doc comments on both
    // for why neither carries SyncableColumns either.
    AppNotifications,
    PairedPrinters,
    // Diagnostic & Crash Logging System — see tables.dart's own doc
    // comment on DiagnosticEvents for why this also isn't a
    // SyncableColumns table.
    DiagnosticEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// The real, on-device constructor — opens (or creates) the actual
  /// SQLite file in the app's own private documents directory, which is
  /// the primary at-rest protection this database relies on (Architecture
  /// Section 11: Android's own app-sandboxing, not a separate encryption
  /// layer, is the deliberate default for this data).
  factory AppDatabase.open() {
    return AppDatabase(_openConnection());
  }

  /// A second, explicit constructor for tests — takes an executor
  /// directly (an in-memory or temp-file NativeDatabase) rather than
  /// reaching for the real on-device path, so database tests (Architecture
  /// Section 13) never touch a real file on the machine running them.
  /// This is not a convenience wrapper around AppDatabase.open(); it's a
  /// genuinely separate construction path, which is what makes it safe
  /// for CI to run these tests in parallel without file contention.
  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase(executor);
  }

  /// The real on-device file path — extracted out of _openConnection
  /// below (Stage 10/Backup integration) so AppDatabaseLifecycle
  /// (app_database_lifecycle.dart) can resolve the exact same path
  /// AppDatabase.open() itself uses, rather than duplicating the
  /// path-construction logic in a second place where it could drift out
  /// of sync with this one.
  static Future<String> resolveDatabasePath() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'fulus_mobile.sqlite');
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_sku '
          'ON products(sku) WHERE deleted_at IS NULL',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode '
          'ON products(barcode) WHERE deleted_at IS NULL',
        );
      },
      // The first real onUpgrade implementation this project has needed
      // — schemaVersion 1 -> 2. Covers every table that's new relative
      // to the bare renamed baseline (the actual, shared schemaVersion 1
      // every contributing session started from) — see this class's own
      // doc comment above for why that's a broader list than any one
      // session, working in isolation, could have reasoned about.
      //
      // Sessions is handled differently from the rest: Stage 2 didn't
      // just ADD a table, it restructured the existing Sessions table
      // (dropped username/email/fullName/backendRole/isActive/
      // lastSyncedAt, added userId/activeLocationId — see tables.dart's
      // own doc comment on Sessions for the full reasoning). A genuine
      // v1 install has an old-shape Sessions table already, so this
      // drops and recreates it rather than trying to ALTER individual
      // columns — safe specifically because a session is a cache of
      // "who's currently signed in," trivially rebuilt by signing in
      // again, not real business data that would be a loss to drop.
      //
      // Every other table below is purely additive — createTable per
      // table is the entire migration for each, no data from version 1
      // needs transforming. Follows the same per-step,
      // individually-reasoned discipline the backend's own Alembic
      // history uses (0001 through 0010, verified directly during the
      // prior audit) rather than a blanket drop-and-recreate of the
      // whole database, which would silently destroy every real
      // business's local sales/stock/customer data on upgrade — the
      // exact same care the BMS -> Fulus rename took with the SQLite
      // filename itself, below.
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.deleteTable('sessions');
          await m.createTable(sessions);
          await m.createTable(users);
          await m.createTable(auditLogs);
          await m.createTable(employees);
          await m.createTable(attendanceRecords);
          await m.createTable(leaveRecords);
          await m.createTable(appNotifications);
          await m.createTable(pairedPrinters);
        }
        if (from < 3) {
          // Nine genuinely new tables — purely additive, same
          // createTable-per-table discipline as the from < 2 block
          // above.
          await m.createTable(categories);
          await m.createTable(suppliers);
          await m.createTable(customerLedgerEntries);
          await m.createTable(salePayments);
          await m.createTable(returnRequests);
          await m.createTable(returnItems);
          await m.createTable(draftCarts);
          await m.createTable(draftCartItems);
          await m.createTable(draftCartPayments);
          await m.createTable(expenseCategories);
          await m.createTable(supplierLedgerEntries);
          await m.createTable(taxRemittances);
          await m.createTable(cashDrawerShifts);

          // New columns on tables that already existed at version 1 —
          // addColumn is the right tool here because every one of these
          // is a genuinely new, nullable-or-defaulted column; nothing
          // about an EXISTING column's own constraint changes.
          await m.addColumn(products, products.tracksStock);
          await m.addColumn(products, products.unit);
          await m.addColumn(products, products.photoPath);
          await m.addColumn(customers, customers.creditLimit);
          await m.addColumn(customers, customers.purchaseCount);
          await m.addColumn(customers, customers.loyaltyThreshold);
          await m.addColumn(customers, customers.photoPath);
          await m.addColumn(customers, customers.lastSyncWarning);
          await m.addColumn(sales, sales.wholeCartDiscount);
          await m.addColumn(suppliers, suppliers.outstandingBalance);

          // SaleItems is the one exception in this block — addColumn
          // alone isn't enough, because productLocalId's own constraint
          // is changing (required -> nullable, for Quick Sale; see that
          // column's own doc comment in tables.dart), not just gaining
          // new columns alongside it. SQLite's ALTER TABLE can't relax a
          // NOT NULL constraint directly, so this needs the
          // create-new-copy-drop-rename Drift's alterTable/TableMigration
          // does internally — the correct tool for changing an existing
          // column, the same way Sessions' own drop-and-recreate above
          // was the correct tool for restructuring an existing table,
          // just narrower in scope (one table, not the whole thing).
          // description/lineDiscount are added in the same pass rather
          // than a separate addColumn call each, since the table is
          // being recreated either way.
          await m.alterTable(
            TableMigration(
              saleItems,
              newColumns: [saleItems.description, saleItems.lineDiscount],
            ),
          );
        }
        if (from < 4) {
          // Sales.cashierUserId — purely additive and nullable, so a
          // plain addColumn is the right tool (same reasoning as the
          // Products/Customers/Suppliers columns in the from < 3 block
          // above), unlike the two FK changes right below it.
          await m.addColumn(sales, sales.cashierUserId);

          // Employees.authUserId and LeaveRecords.decidedBy: the
          // column itself isn't changing shape (still a nullable text
          // column, same name, same nullability) — only the DDL-level
          // REFERENCES clause is being added, now that Users exists in
          // this schema. SQLite has no ALTER TABLE for adding a
          // constraint to an existing column, so this needs the same
          // recreate-copy-drop-rename TableMigration does internally,
          // the same tool (and the same reason — an existing column's
          // own constraint changing, not a new column being added)
          // SaleItems needed above. No `newColumns` here: every column
          // in the new table shape already exists, under the same
          // name, in the old one — this is a straight copy, not a
          // partial one.
          await m.alterTable(TableMigration(employees));
          await m.alterTable(TableMigration(leaveRecords));
        }
        if (from < 5) {
          // Expenses.receiptPhotoPath — purely additive and nullable,
          // same addColumn treatment as Products.photoPath/
          // Customers.photoPath got above; no data transformation
          // needed for existing rows, which simply start out with no
          // receipt photo attached.
          await m.addColumn(expenses, expenses.receiptPhotoPath);
        }
        if (from < 6) {
          // Same two indexes onCreate gets, added here for installs
          // that already have a products table. Wrapped individually:
          // this is defense-in-depth, not the primary guarantee (the
          // generator in product_import_engine.dart already avoids
          // collisions on new writes), so an install that somehow
          // already has a duplicate sku or barcode just doesn't get
          // the index for that column, rather than the whole upgrade
          // failing over it.
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_sku '
              'ON products(sku) WHERE deleted_at IS NULL',
            );
          } catch (_) {
            // Pre-existing duplicate sku on this device — skip the index.
          }
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode '
              'ON products(barcode) WHERE deleted_at IS NULL',
            );
          } catch (_) {
            // Pre-existing duplicate barcode on this device — skip the index.
          }
        }
        if (from < 7) {
          // Purely additive, nullable-with-default — every existing
          // return row simply starts out as "not a void" (correct: it
          // predates the concept, and every return created before this
          // was a customer return by definition).
          await m.addColumn(returnRequests, returnRequests.isVoid);
        }
        if (from < 8) {
          // One new table, no existing data touched — see this class's
          // own SEVENTH NOTE above and DiagnosticEvents' own doc
          // comment in tables.dart.
          await m.createTable(diagnosticEvents);
        }
      },
      beforeOpen: (details) async {
        // Foreign keys are OFF by default in sqlite3 unless explicitly
        // enabled per connection — mirroring the exact same fact
        // confirmed directly in the backend's own database/session.py
        // during the audit (PRAGMA foreign_keys=ON, paired correctly
        // with check_same_thread=False there). The mobile local database
        // needs this pragma for precisely the same reason: several
        // tables above declare real foreign keys (SaleItems ->
        // Sales/Products, StockMovements -> Locations, Sessions ->
        // Users), and those constraints are silently unenforced without
        // this.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final path = await AppDatabase.resolveDatabasePath();
    final file = File(path);

    // One-time migration for installs upgrading across the BMS -> Fulus
    // rename. This file is the on-device source of truth for sales,
    // stock, customers, and the offline sync queue — not cosmetic
    // branding. If nothing exists yet under the new filename but the old
    // 'bms_mobile.sqlite' does, move it over so an upgrading till keeps
    // its local data instead of silently starting from an empty database
    // (which, on a device that's ever gone offline, could mean losing
    // sales that haven't synced to the backend yet). A genuinely fresh
    // install has neither file, so this is a no-op for new installs.
    if (!await file.exists()) {
      final legacyFile = File(p.join(file.parent.path, 'bms_mobile.sqlite'));
      if (await legacyFile.exists()) {
        await legacyFile.rename(file.path);
      }
    }

    return NativeDatabase.createInBackground(file);
  });
}
