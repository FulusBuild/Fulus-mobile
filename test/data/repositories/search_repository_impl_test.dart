import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/search_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/search_result.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real Drift-backed, no mocks — Architecture Section 13's integration-test
/// layer, the same pattern test/sync/sync_engine_test.dart already uses
/// (AppDatabase.forTesting(NativeDatabase.memory())). Chosen over a mocked
/// AppDatabase specifically because what this repository actually needs
/// verified is the SQL query logic itself (LIKE matching across three
/// tables, deletedAt exclusion, the limit) — a mock would just assert
/// this class calls some method, telling us nothing about whether the
/// query it builds is actually correct.
void main() {
  late AppDatabase db;
  late SearchRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = SearchRepositoryImpl(db: db);

    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            localId: 'loc-1',
            name: 'Main Branch',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedProduct({
    required String localId,
    required String name,
    String sku = 'SKU-0',
    String? barcode,
    DateTime? deletedAt,
  }) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: localId,
            name: name,
            sku: sku,
            barcode: Value(barcode),
            costPrice: 100,
            sellingPrice: 150,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<void> seedCustomer({
    required String localId,
    required String name,
    String? phone,
    DateTime? deletedAt,
  }) {
    return db.into(db.customers).insert(
          CustomersCompanion.insert(
            localId: localId,
            name: name,
            phone: Value(phone),
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<void> seedSale({
    required String localId,
    String? invoiceNumber,
    String? notes,
    DateTime? deletedAt,
  }) {
    return db.into(db.sales).insert(
          SalesCompanion.insert(
            localId: localId,
            clientReference: 'ref-$localId',
            locationId: 'loc-1',
            saleDate: DateTime(2026, 2, 1),
            subtotal: 1000,
            total: 1000,
            createdAt: DateTime(2026, 2, 1),
            updatedAt: DateTime(2026, 2, 1),
            syncStatus: SyncStatus.settled,
            invoiceNumber: Value(invoiceNumber),
            notes: Value(notes),
            deletedAt: Value(deletedAt),
          ),
        );
  }

  test('empty query returns empty results without querying the database', () async {
    final results = await repository.search('   ');
    expect(results.total, 0);
    expect(results, SearchResults.empty('   '));
  });

  test('finds a product by a substring of its name, case-insensitively', () async {
    await seedProduct(localId: 'p1', name: 'Golden Penny Semovita');
    final results = await repository.search('penny');
    expect(results.products, hasLength(1));
    expect(results.products.first.entityId, 'p1');
    expect(results.products.first.title, 'Golden Penny Semovita');
  });

  test('finds a product by SKU and by barcode independently', () async {
    await seedProduct(localId: 'p1', name: 'Rice', sku: 'RICE-50KG');
    await seedProduct(localId: 'p2', name: 'Beans', barcode: '6001234567890');

    final bySku = await repository.search('RICE-50');
    expect(bySku.products.map((r) => r.entityId), ['p1']);

    final byBarcode = await repository.search('6001234');
    expect(byBarcode.products.map((r) => r.entityId), ['p2']);
  });

  test('excludes a soft-deleted product from results', () async {
    await seedProduct(localId: 'p1', name: 'Discontinued Item', deletedAt: DateTime.now());
    final results = await repository.search('discontinued');
    expect(results.products, isEmpty);
  });

  test('finds a customer by name or phone', () async {
    await seedCustomer(localId: 'c1', name: 'Adaeze Okafor', phone: '08012345678');
    expect((await repository.search('Adaeze')).customers, hasLength(1));
    expect((await repository.search('08012345678')).customers, hasLength(1));
  });

  test('finds a sale by invoice number, excludes a soft-deleted (cancelled) one', () async {
    await seedSale(localId: 's1', invoiceNumber: 'INV-1001');
    await seedSale(localId: 's2', invoiceNumber: 'INV-1002', deletedAt: DateTime.now());

    final results = await repository.search('INV-100');
    expect(results.sales.map((r) => r.entityId), ['s1']);
  });

  test('results are grouped per module and also available flattened via .all', () async {
    await seedProduct(localId: 'p1', name: 'Zebra brand rice');
    await seedCustomer(localId: 'c1', name: 'Zebra Traders Ltd');

    final results = await repository.search('zebra');
    expect(results.products, hasLength(1));
    expect(results.customers, hasLength(1));
    expect(results.all, hasLength(2));
    expect(results.total, 2);
  });

  test('respects limitPerModule', () async {
    for (var i = 0; i < 10; i++) {
      await seedProduct(localId: 'p$i', name: 'Matchable Product $i', sku: 'SKU-$i');
    }
    final results = await repository.search('Matchable', limitPerModule: 3);
    expect(results.products, hasLength(3));
  });

  test('a query with no matches anywhere returns empty, grouped lists', () async {
    await seedProduct(localId: 'p1', name: 'Rice');
    final results = await repository.search('nonexistent-xyz');
    expect(results.total, 0);
    expect(results.products, isEmpty);
    expect(results.customers, isEmpty);
    expect(results.sales, isEmpty);
  });
}
