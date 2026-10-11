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
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });
}
