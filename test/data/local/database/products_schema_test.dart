import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  ProductsCompanion product({
    required String localId,
    required String sku,
    String? barcode,
    DateTime? deletedAt,
  }) {
    final now = DateTime(2026, 1, 1);
    return ProductsCompanion.insert(
      localId: localId,
      name: 'Product $localId',
      sku: sku,
      barcode: Value(barcode),
      costPrice: 0,
      sellingPrice: 0,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
      deletedAt: Value(deletedAt),
    );
  }

  test('rejects a second active product with the same sku', () async {
    await db.into(db.products).insert(product(localId: 'p1', sku: 'RICE50'));

    expect(
      () => db.into(db.products).insert(product(localId: 'p2', sku: 'RICE50')),
      throwsA(anything),
    );
  });

  test('rejects a second active product with the same barcode', () async {
    await db.into(db.products).insert(product(localId: 'p1', sku: 'A', barcode: '6001234567890'));

    expect(
      () => db.into(db.products).insert(product(localId: 'p2', sku: 'B', barcode: '6001234567890')),
      throwsA(anything),
    );
  });

  test('allows multiple products with no barcode', () async {
    await db.into(db.products).insert(product(localId: 'p1', sku: 'A'));
    await db.into(db.products).insert(product(localId: 'p2', sku: 'B'));

    final rows = await db.select(db.products).get();
    expect(rows, hasLength(2));
  });

  test('a soft-deleted product\'s sku and barcode can be reused', () async {
    await db.into(db.products).insert(
          product(localId: 'p1', sku: 'RICE50', barcode: '6001234567890', deletedAt: DateTime(2026, 2, 1)),
        );

    await db.into(db.products).insert(product(localId: 'p2', sku: 'RICE50', barcode: '6001234567890'));

    final active = await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
    expect(active, hasLength(1));
    expect(active.single.localId, 'p2');
  });
}
