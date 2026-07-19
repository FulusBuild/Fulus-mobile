import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// The local database — Architecture Section 3's Drift choice, and the
/// single source of truth on-device per the brief's own stated
/// architecture principle ("the local database is the source of truth").
///
/// schemaVersion starts at 1 deliberately, not some placeholder like 0 —
/// this IS the first real migration, matching the backend's own Alembic
/// discipline (0001_initial.py, verified directly during the audit) of
/// treating the very first schema as version 1, not an implicit
/// unversioned starting point.
@DriftDatabase(
  tables: [
    Locations,
    Sessions,
    Products,
    ProductStockLevels,
    Customers,
    Sales,
    SaleItems,
    StockMovements,
    Expenses,
    IncomeRecords,
    SyncQueueItems,
    BusinessSettings,
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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      // onUpgrade is intentionally left as the default (which throws if
      // ever actually invoked) rather than a placeholder empty function —
      // there is no schema version 0 to upgrade FROM, so a real
      // onUpgrade case genuinely cannot occur yet. The first real
      // migration this project ever needs (schemaVersion 1 -> 2) is where
      // this gets its first real implementation, following the same
      // per-step, reviewed discipline the backend's Alembic history uses
      // (verified directly: migrations 0001 through 0010, each a
      // deliberate, individually-reasoned step) — not written speculatively
      // now for a version-2 schema that doesn't exist.
      beforeOpen: (details) async {
        // Foreign keys are OFF by default in sqlite3 unless explicitly
        // enabled per connection — mirroring the exact same fact I
        // confirmed directly in the backend's own database/session.py
        // during the audit (PRAGMA foreign_keys=ON, paired correctly
        // with check_same_thread=False there). The mobile local database
        // needs this pragma for precisely the same reason: several
        // tables above declare real foreign keys (SaleItems ->
        // Sales/Products, StockMovements -> Locations), and those
        // constraints are silently unenforced without this.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'bms_mobile.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
