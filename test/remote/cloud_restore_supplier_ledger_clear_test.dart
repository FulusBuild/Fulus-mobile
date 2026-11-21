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
              updatedAt: DateTime.now(),
              syncStatus: SyncStatus.settled,
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

  test(
    'restores canonical supplier ledger references and money units',
    () async {
      final timestamp = DateTime.utc(2026, 1, 20).toIso8601String();
      await CloudRestoreImporter(db).importSnapshot({
        'version': 7,
        'locations': [
          {
            'id': 'location-1',
            'name': 'Main',
            'status': 'active',
            'created_at': timestamp,
            'updated_at': timestamp,
          },
        ],
        'suppliers': [
          {
            'id': 'supplier-1',
            'name': 'Ledger Supplier',
            'outstanding_balance': '12.34',
            'created_at': timestamp,
            'updated_at': timestamp,
          },
        ],
        'supplier_ledger_entries': [
          {
            'id': 'ledger-1',
            'supplier_id': 'supplier-1',
            'location_id': 'location-1',
            'entry_type': 'payment_made',
            'amount': '7.66',
            'balance_after': '12.34',
            'operation_id': 'supplier-payment-1',
            'payment_method': 'bank_transfer',
            'created_at': timestamp,
            'updated_at': timestamp,
          },
        ],
      });

      final ledger = await db.select(db.supplierLedgerEntries).getSingle();
      expect(ledger.serverId, 'ledger-1');
      expect(ledger.supplierLocalId, 'supplier-1');
      expect(ledger.locationLocalId, 'location-1');
      expect(ledger.entryType, 'paymentMade');
      expect(ledger.amount, 766);
      expect(ledger.syncStatus, SyncStatus.settled);
    },
  );
}
