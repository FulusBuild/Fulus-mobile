import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v25 upgrade adds stock adjustment column and relaxes quantity', () async {
    final directory =
        await Directory.systemTemp.createTemp('fulus-stock-movement-migration-');
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
      final columns =
          await upgraded.customSelect('PRAGMA table_info(stock_movements)').get();
      final newQuantity = columns.where(
        (row) => row.data['name'] == 'new_quantity',
      );
      final quantity = columns.where(
        (row) => row.data['name'] == 'quantity',
      );

      expect(newQuantity, hasLength(1));
      expect(quantity, hasLength(1));
      expect(quantity.single.data['notnull'], 0);

      final preserved = await upgraded.customSelect(
        "SELECT quantity, new_quantity FROM stock_movements "
        "WHERE local_id = 'move-1'",
      ).get();
      expect(preserved, hasLength(1));
      expect(preserved.single.data['quantity'], 4);
      expect(preserved.single.data['new_quantity'], isNull);
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
}
