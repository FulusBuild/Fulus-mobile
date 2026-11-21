import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'v28 upgrade queues only supplier ledger entries with known locations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fulus-supplier-ledger-sync-migration-',
      );
      final path = '${directory.path}/fulus.db';
      final current = AppDatabase.forTesting(NativeDatabase(File(path)));
      await current.customSelect('SELECT 1').get();
      final now = DateTime.now();
      await current
          .into(current.locations)
          .insert(
            LocationsCompanion.insert(
              localId: 'loc-1',
              name: 'Main',
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
      await current
          .into(current.suppliers)
          .insert(
            SuppliersCompanion.insert(
              localId: 'supplier-1',
              name: 'Supplier',
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
      for (final entry in [
        ('located-entry', 'loc-1'),
        ('unlocated-entry', null),
      ]) {
        await current
            .into(current.supplierLedgerEntries)
            .insert(
              SupplierLedgerEntriesCompanion.insert(
                localId: entry.$1,
                supplierLocalId: 'supplier-1',
                locationLocalId: Value(entry.$2),
                entryType: 'paymentMade',
                amount: 100,
                createdAt: now,
                updatedAt: now,
                syncStatus: SyncStatus.settled,
              ),
            );
      }
      await current.close();

      final raw = sqlite3.sqlite3.open(path);
      try {
        raw.execute('PRAGMA user_version = 28');
      } finally {
        raw.close();
      }

      final upgraded = AppDatabase.forTesting(NativeDatabase(File(path)));
      try {
        final queued = await upgraded.select(upgraded.syncQueueItems).get();
        expect(queued.map((item) => item.id), [
          'supplier-ledger:located-entry',
        ]);
        expect(queued.single.entityType, 'supplier_ledger');
        expect(queued.single.entityLocalId, 'located-entry');
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'v26 upgrade adds nullable cash drawer attribution to supplier payments',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fulus-supplier-drawer-migration-',
      );
      final path = '${directory.path}/fulus.db';

      final current = AppDatabase.forTesting(NativeDatabase(File(path)));
      await current.customSelect('SELECT 1').get();
      await current.close();

      final raw = sqlite3.sqlite3.open(path);
      try {
        raw.execute('PRAGMA foreign_keys = OFF');
        raw.execute('DROP TABLE supplier_ledger_entries');
        raw.execute('''
        CREATE TABLE supplier_ledger_entries (
          local_id TEXT NOT NULL PRIMARY KEY,
          supplier_local_id TEXT NOT NULL REFERENCES suppliers(local_id),
          entry_type TEXT NOT NULL,
          amount INTEGER NOT NULL,
          payment_method TEXT,
          note TEXT,
          stock_movement_local_id TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
        raw.execute('PRAGMA user_version = 26');
      } finally {
        raw.close();
      }

      final upgraded = AppDatabase.forTesting(NativeDatabase(File(path)));
      try {
        final columns = await upgraded
            .customSelect('PRAGMA table_info(supplier_ledger_entries)')
            .get();
        expect(
          columns.any(
            (row) => row.data['name'] == 'cash_drawer_shift_local_id',
          ),
          isTrue,
        );
        expect(
          columns.any((row) => row.data['name'] == 'location_local_id'),
          isTrue,
        );
        final foreignKeys = await upgraded
            .customSelect('PRAGMA foreign_key_list(supplier_ledger_entries)')
            .get();
        expect(
          foreignKeys.any(
            (row) =>
                row.data['table'] == 'cash_drawer_shifts' &&
                row.data['from'] == 'cash_drawer_shift_local_id',
          ),
          isTrue,
        );
        expect(
          foreignKeys.any(
            (row) =>
                row.data['table'] == 'locations' &&
                row.data['from'] == 'location_local_id',
          ),
          isTrue,
        );
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('v25 upgrade adds stock adjustment column and relaxes quantity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fulus-stock-movement-migration-',
    );
    final path = '${directory.path}/fulus.db';

    final current = AppDatabase.forTesting(NativeDatabase(File(path)));
    await current.customSelect('SELECT 1').get();
    await current.close();

    // Recreate the stock_movements shape that existed before the missing
    // adjustment migration, while marking the rest of the database as v25.
    final raw = sqlite3.sqlite3.open(path);
    try {
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(
        "INSERT INTO locations "
        "(local_id, created_at, updated_at, sync_status, name) "
        "VALUES ('loc-1', 1, 1, 'settled', 'Main')",
      );
      raw.execute(
        "INSERT INTO products "
        "(local_id, created_at, updated_at, sync_status, name, sku, "
        "cost_price, selling_price) "
        "VALUES ('prod-1', 1, 1, 'settled', 'Test product', 'SKU-1', 0, 0)",
      );
      raw.execute('DROP TABLE stock_movements');
      raw.execute('''
        CREATE TABLE stock_movements (
          local_id TEXT NOT NULL PRIMARY KEY,
          server_id TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status TEXT NOT NULL,
          deleted_at INTEGER,
          product_local_id TEXT NOT NULL REFERENCES products(local_id),
          location_id TEXT NOT NULL REFERENCES locations(local_id),
          to_location_id TEXT REFERENCES locations(local_id),
          movement_type TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          reason TEXT
        )
      ''');
      raw.execute(
        "INSERT INTO stock_movements "
        "(local_id, server_id, created_at, updated_at, sync_status, deleted_at, "
        "product_local_id, location_id, to_location_id, movement_type, quantity, reason) "
        "VALUES ('move-1', NULL, 1, 1, 'settled', NULL, 'prod-1', 'loc-1', "
        "NULL, 'in', 4, 'legacy seed')",
      );
      raw.execute('PRAGMA user_version = 25');
    } finally {
      raw.close();
    }

    final upgraded = AppDatabase.forTesting(NativeDatabase(File(path)));
    try {
      final columns = await upgraded
          .customSelect('PRAGMA table_info(stock_movements)')
          .get();
      final newQuantity = columns.where(
        (row) => row.data['name'] == 'new_quantity',
      );
      final quantity = columns.where((row) => row.data['name'] == 'quantity');

      expect(newQuantity, hasLength(1));
      expect(quantity, hasLength(1));
      expect(quantity.single.data['notnull'], 0);

      final preserved = await upgraded
          .customSelect(
            "SELECT quantity, new_quantity FROM stock_movements "
            "WHERE local_id = 'move-1'",
          )
          .get();
      expect(preserved, hasLength(1));
      expect(preserved.single.data['quantity'], 4);
      expect(preserved.single.data['new_quantity'], isNull);
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
}
