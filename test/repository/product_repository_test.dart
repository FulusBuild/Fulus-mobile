import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/local/database/tables.dart';
import 'package:bms_mobile/data/remote/endpoints/products_api.dart';
import 'package:bms_mobile/data/repositories/product_repository_impl.dart';
import 'package:bms_mobile/domain/entities/product.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProductsApi extends Mock implements ProductsApi {}

void main() {
  late AppDatabase db;
  late MockProductsApi productsApi;
  late ProductRepositoryImpl repository;

  const locationId = 'loc-1';

  ProductResponseDto product(String id, {int currentStock = 0, int lowStockThreshold = 10}) {
    return ProductResponseDto(
      id: id,
      name: 'Product $id',
      sku: 'SKU-$id',
      costPrice: 5.0,
      sellingPrice: 10.0,
      lowStockThreshold: lowStockThreshold,
      currentStock: currentStock,
      isActive: true,
      isLowStock: currentStock <= lowStockThreshold,
      stockValue: 5.0 * currentStock,
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    productsApi = MockProductsApi();
    repository = ProductRepositoryImpl(db: db, productsApi: productsApi);
  });

  tearDown(() async {
    await db.close();
  });

  group('syncFromServer', () {
    test('writes catalog fields even with no local Location yet', () async {
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1', currentStock: 20)],
          total: 1,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );

      await repository.syncFromServer();

      final rows = await db.select(db.products).get();
      expect(rows, hasLength(1));
      expect(rows.single.localId, 'p1');
      expect(rows.single.serverId, 'p1');

      // No Location row exists — stock-level reconciliation has nowhere
      // to key to and is skipped for this pass (see syncFromServer's own
      // comment), not an error.
      final stockLevels = await db.select(db.productStockLevels).get();
      expect(stockLevels, isEmpty);
    });

    test('also writes ProductStockLevels once a Location exists', () async {
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: locationId,
            name: 'Main Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1', currentStock: 20)],
          total: 1,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );

      await repository.syncFromServer();

      final stockLevel = await (db.select(db.productStockLevels)
            ..where((s) => s.productLocalId.equals('p1') & s.locationLocalId.equals(locationId)))
          .getSingle();
      expect(stockLevel.currentStock, 20);
    });

    test('follows pagination across multiple pages', () async {
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1'), product('p2')],
          total: 3,
          page: 1,
          pageSize: 2,
          totalPages: 2,
        ),
      );
      when(() => productsApi.listProducts(page: 2)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p3')],
          total: 3,
          page: 2,
          pageSize: 2,
          totalPages: 2,
        ),
      );

      await repository.syncFromServer();

      final rows = await db.select(db.products).get();
      expect(rows.map((r) => r.localId).toSet(), {'p1', 'p2', 'p3'});
      verify(() => productsApi.listProducts(page: 1)).called(1);
      verify(() => productsApi.listProducts(page: 2)).called(1);
    });

    test('re-syncing the same product updates it rather than duplicating', () async {
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1', currentStock: 20)],
          total: 1,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );
      await repository.syncFromServer();

      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1', currentStock: 999)],
          total: 1,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );
      await repository.syncFromServer();

      final rows = await db.select(db.products).get();
      expect(rows, hasLength(1));
    });
  });

  group('reconcileStockLevel', () {
    test('writes ProductStockLevels for a product that already exists locally', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            serverId: const Value('p1'),
            name: 'Product p1',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      await repository.reconcileStockLevel(
        productLocalId: 'p1',
        locationId: locationId,
        currentStock: 7,
      );

      final stockLevel = await (db.select(db.productStockLevels)
            ..where((s) => s.productLocalId.equals('p1') & s.locationLocalId.equals(locationId)))
          .getSingle();
      expect(stockLevel.currentStock, 7);
    });

    test('throws when the product has never been synced down', () async {
      await expectLater(
        repository.reconcileStockLevel(
          productLocalId: 'never-synced',
          locationId: locationId,
          currentStock: 5,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('reads', () {
    setUp(() async {
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: locationId,
            name: 'Main Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
    });

    test('watchProducts joins in currentStock for the given location', () async {
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [product('p1', currentStock: 20)],
          total: 1,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );
      await repository.syncFromServer();

      final emitted = await repository.watchProducts(locationId: locationId).first;

      expect(emitted, hasLength(1));
      expect(emitted.single.currentStock, 20);
      expect(emitted.single.product.localId, 'p1');
    });

    test('watchProducts treats a product with no stock-level row as zero', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Product p1',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      final emitted = await repository.watchProducts(locationId: locationId).first;

      expect(emitted.single.currentStock, 0);
    });

    test('watchProducts excludes inactive products', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Discontinued',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            isActive: const Value(false),
          ));

      final emitted = await repository.watchProducts(locationId: locationId).first;

      expect(emitted, isEmpty);
    });

    test('getProductById finds a product even if inactive', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Discontinued',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            isActive: const Value(false),
          ));

      final result = await repository.getProductById('p1', locationId: locationId);

      expect(result, isNotNull);
      expect(result!.product.isActive, false);
    });

    test('watchLowStockProducts only returns products at or below their threshold', () async {
      when(() => productsApi.listProducts(page: 1)).thenAnswer(
        (_) async => ProductListResponseDto(
          items: [
            product('low', currentStock: 2, lowStockThreshold: 10),
            product('healthy', currentStock: 50, lowStockThreshold: 10),
          ],
          total: 2,
          page: 1,
          pageSize: 200,
          totalPages: 1,
        ),
      );
      await repository.syncFromServer();

      final emitted = await repository.watchLowStockProducts(locationId: locationId).first;

      expect(emitted, hasLength(1));
      expect(emitted.single.product.localId, 'low');
    });

    test('watchLowStockProducts excludes a product with no stock-level row', () async {
      // Unknown stock, not zero stock — see watchLowStockProducts' own
      // comment on why this is an inner join rather than a left join.
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Never stocked here',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      final emitted = await repository.watchLowStockProducts(locationId: locationId).first;

      expect(emitted, isEmpty);
    });
  });
}
