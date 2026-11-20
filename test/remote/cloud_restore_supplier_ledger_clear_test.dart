import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/cloud_restore_importer.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'clears device-local supplier ledger before replacing suppliers',
    () async {
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              localId: 'old-supplier',
              name: 'Old supplier',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              syncStatus: SyncStatus.settled,
              outstandingBalance: const Value(25000),
            ),
          );
      await db
          .into(db.supplierLedgerEntries)
          .insert(
            SupplierLedgerEntriesCompanion.insert(
              localId: 'old-supplier-entry',
              supplierLocalId: 'old-supplier',
              entryType: 'stockPurchaseOnCredit',
              amount: 25000,
              createdAt: DateTime.now(),
            ),
          );

      await CloudRestoreImporter(db).importSnapshot({
        'version': 7,
        'locations': [],
        'categories': [],
        'suppliers': [],
      });

      expect(await db.select(db.suppliers).get(), isEmpty);
      expect(await db.select(db.supplierLedgerEntries).get(), isEmpty);
    },
  );
}
