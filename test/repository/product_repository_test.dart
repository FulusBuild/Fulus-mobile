import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/products_api.dart';
import 'package:fulus_mobile/data/repositories/product_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProductsApi extends Mock implements ProductsApi {}

void main() {
  late AppDatabase db;
  late MockProductsApi productsApi;
  late SyncQueue syncQueue;
  late ProductRepositoryImpl repository;

  const locationId = 'loc-1';

  setUpAll(() {
    // Needed wherever a test uses `any()`/`captureAny()` for a
    // ProductCreateDto argument (e.g. verifyNever(() =>
    // productsApi.createProduct(any()))) — mocktail needs a real
    // instance to stand in for the matcher, never actually used.
    registerFallbackValue(const ProductCreateDto(
      name: 'fallback',
      sku: 'fallback-sku',
      costPrice: 0,
      sellingPrice: 0,
    ));
  });

  Future<void> seedLocation() {
    return db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  }

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
    syncQueue = SyncQueue(db);
    repository = ProductRepositoryImpl(db: db, productsApi: productsApi, syncQueue: syncQueue);
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
      // ProductStockLevels.locationLocalId is a real FK reference to
      // Locations — must exist before this insert, same requirement as
      // every other write into this table throughout this file. Missed
      // here originally because this group has no shared setUp seeding
      // one the way the 'reads' group below does; caught by a real CI
      // run (FOREIGN KEY constraint failed, code 787), not by any of
      // the manual checks this whole batch was built under.
      await db.into(db.locations).insert(LocationsCompanion.insert(
            localId: locationId,
            name: 'Main Store',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));
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

    test('getProductByBarcode finds a match by barcode alone', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Coca-Cola 50cl',
            sku: 'SKU-p1',
            barcode: const Value('6001234567890'),
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      final result = await repository.getProductByBarcode('6001234567890', locationId: locationId);

      expect(result, isNotNull);
      expect(result!.product.localId, 'p1');
    });

    test('getProductByBarcode returns null for an unknown barcode', () async {
      final result = await repository.getProductByBarcode('does-not-exist', locationId: locationId);
      expect(result, isNull);
    });

    test('getProductBySku finds a match by SKU alone', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'Coca-Cola 50cl',
            sku: 'COKE-50CL',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      final result = await repository.getProductBySku('COKE-50CL', locationId: locationId);

      expect(result, isNotNull);
      expect(result!.product.localId, 'p1');
    });
  });

  group('createProduct', () {
    test('writes the product locally and returns immediately, without awaiting the network', () async {
      await seedLocation();

      final result = await repository.createProduct(const ProductDraft(
        name: 'New Product',
        sku: 'NEW-1',
        costPrice: 3.0,
        sellingPrice: 6.0,
        locationId: locationId,
      ));

      expect(result.name, 'New Product');
      verifyNever(() => productsApi.createProduct(any()));

      final rows = await db.select(db.products).get();
      expect(rows.single.name, 'New Product');
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('seeds a ProductStockLevels row even when initialStock is 0', () async {
      await seedLocation();

      final result = await repository.createProduct(const ProductDraft(
        name: 'New Product',
        sku: 'NEW-1',
        costPrice: 3.0,
        sellingPrice: 6.0,
        locationId: locationId,
      ));

      final stockLevel = await (db.select(db.productStockLevels)
            ..where((s) => s.productLocalId.equals(result.localId) & s.locationLocalId.equals(locationId)))
          .getSingle();
      expect(stockLevel.currentStock, 0);
    });

    test('seeds ProductStockLevels with a nonzero initialStock', () async {
      await seedLocation();

      final result = await repository.createProduct(const ProductDraft(
        name: 'New Product',
        sku: 'NEW-1',
        costPrice: 3.0,
        sellingPrice: 6.0,
        locationId: locationId,
        initialStock: 15,
      ));

      final stockLevel = await (db.select(db.productStockLevels)
            ..where((s) => s.productLocalId.equals(result.localId) & s.locationLocalId.equals(locationId)))
          .getSingle();
      expect(stockLevel.currentStock, 15);
    });

    test('enqueues exactly one high-priority-tier sync task', () async {
      await seedLocation();

      await repository.createProduct(const ProductDraft(
        name: 'New Product',
        sku: 'NEW-1',
        costPrice: 3.0,
        sellingPrice: 6.0,
        locationId: locationId,
      ));

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'product');
      expect(queued.single.operation, 'create');
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });

    // Regression coverage for a confirmed business-logic gap found
    // during audit: AddEditProductScreen already rejected sellingPrice
    // <= 0 (see that screen's own `_save`), so this specific path
    // wasn't directly reachable through the normal UI — but nothing at
    // this layer caught it either. costPrice had no guard anywhere at
    // all, UI or repository, despite flowing straight into every COGS
    // calculation in the app (costPriceAtSale is captured from this
    // exact field at cart-add time).
    group('price validation (bug fix)', () {
      test('rejects a zero sellingPrice', () async {
        await seedLocation();
        await expectLater(
          repository.createProduct(const ProductDraft(
            name: 'Free Sample',
            sku: 'FREE-1',
            costPrice: 3.0,
            sellingPrice: 0,
            locationId: locationId,
          )),
          throwsArgumentError,
        );
      });

      test('rejects a negative sellingPrice', () async {
        await seedLocation();
        await expectLater(
          repository.createProduct(const ProductDraft(
            name: 'Bad Product',
            sku: 'BAD-1',
            costPrice: 3.0,
            sellingPrice: -6.0,
            locationId: locationId,
          )),
          throwsArgumentError,
        );
      });

      test('rejects a negative costPrice', () async {
        await seedLocation();
        await expectLater(
          repository.createProduct(const ProductDraft(
            name: 'Bad Product',
            sku: 'BAD-2',
            costPrice: -3.0,
            sellingPrice: 6.0,
            locationId: locationId,
          )),
          throwsArgumentError,
        );
      });

      test('allows a zero costPrice — "cost not yet known" is a '
          'legitimate state here, same as Quick Sale items', () async {
        await seedLocation();
        final result = await repository.createProduct(const ProductDraft(
          name: 'New Product',
          sku: 'NEW-2',
          costPrice: 0,
          sellingPrice: 6.0,
          locationId: locationId,
        ));
        expect(result.costPrice, 0);
      });

      test('a rejected creation writes nothing to the local database at '
          'all — no product row, no stock row, no sync task', () async {
        await seedLocation();
        try {
          await repository.createProduct(const ProductDraft(
            name: 'Bad Product',
            sku: 'BAD-3',
            costPrice: 3.0,
            sellingPrice: -6.0,
            locationId: locationId,
          ));
        } on ArgumentError {
          // expected — the guard fires before any write happens
        }

        final productRows = await db.select(db.products).get();
        expect(productRows, isEmpty);
        final queued = await db.select(db.syncQueueItems).get();
        expect(queued, isEmpty);
      });
    });
  });

  group('updateProduct', () {
    test('changes only the fields passed, leaving the rest untouched', () async {
      await seedLocation();
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            serverId: const Value('p1'),
            name: 'Original Name',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      await repository.updateProduct(localId: 'p1', sellingPrice: 12.0);

      final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
      expect(row.sellingPrice, 12.0);
      expect(row.name, 'Original Name'); // untouched
      expect(row.sku, 'SKU-p1'); // untouched
    });

    test('marks the row pending and enqueues an update sync task', () async {
      await seedLocation();
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            serverId: const Value('p1'),
            name: 'Original Name',
            sku: 'SKU-p1',
            costPrice: 5.0,
            sellingPrice: 10.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
          ));

      await repository.updateProduct(localId: 'p1', sellingPrice: 12.0);

      final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
      expect(row.syncStatus, SyncStatus.pending);

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued.single.entityType, 'product');
      expect(queued.single.operation, 'update');
    });

    // Regression coverage for the same confirmed gap as createProduct's
    // own "price validation (bug fix)" group above — see that group's
    // doc comment for the full reasoning. Only fires when the field is
    // actually being changed here, matching this method's existing
    // partial-update convention.
    group('price validation (bug fix)', () {
      Future<void> seedExistingProduct() async {
        await seedLocation();
        await db.into(db.products).insert(ProductsCompanion.insert(
              localId: 'p1',
              serverId: const Value('p1'),
              name: 'Original Name',
              sku: 'SKU-p1',
              costPrice: 5.0,
              sellingPrice: 10.0,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              syncStatus: SyncStatus.settled,
            ));
      }

      test('rejects updating sellingPrice to zero or below', () async {
        await seedExistingProduct();
        await expectLater(
          repository.updateProduct(localId: 'p1', sellingPrice: 0),
          throwsArgumentError,
        );
        await expectLater(
          repository.updateProduct(localId: 'p1', sellingPrice: -5.0),
          throwsArgumentError,
        );
      });

      test('rejects updating costPrice to a negative value', () async {
        await seedExistingProduct();
        await expectLater(
          repository.updateProduct(localId: 'p1', costPrice: -1.0),
          throwsArgumentError,
        );
      });

      test('allows updating costPrice to exactly zero', () async {
        await seedExistingProduct();
        await repository.updateProduct(localId: 'p1', costPrice: 0);
        final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
        expect(row.costPrice, 0);
      });

      test('leaving sellingPrice/costPrice unpassed never triggers the '
          'guard, even though the existing row already has values',
          () async {
        await seedExistingProduct();
        // Only updating name — sellingPrice/costPrice stay absent, not
        // re-validated against the row's own existing values.
        await expectLater(
          repository.updateProduct(localId: 'p1', name: 'New Name'),
          completes,
        );
      });

      test('a rejected update leaves the existing row completely '
          'unchanged, not partially applied', () async {
        await seedExistingProduct();
        try {
          await repository.updateProduct(
            localId: 'p1',
            name: 'Should Not Stick',
            sellingPrice: -5.0,
          );
        } on ArgumentError {
          // expected
        }

        final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
        expect(row.name, 'Original Name');
        expect(row.sellingPrice, 10.0);
        expect(row.syncStatus, SyncStatus.settled); // never marked pending
        final queued = await db.select(db.syncQueueItems).get();
        expect(queued, isEmpty);
      });
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: 'p1',
            name: 'New Product',
            sku: 'NEW-1',
            costPrice: 3.0,
            sellingPrice: 6.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.pending,
          ));

      await repository.markSynced(localId: 'p1', serverId: 'server-p1');

      final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
      expect(row.serverId, 'server-p1');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
  group('catalog integrity', () {
    Future<void> seedProduct(String id, {String sku = 'SKU-p1', String? barcode}) async {
      await seedLocation();
      await db.into(db.products).insert(ProductsCompanion.insert(
        localId: id,
        name: 'Product $id',
        sku: sku,
        barcode: barcode == null ? const Value.absent() : Value(barcode),
        costPrice: 5,
        sellingPrice: 10,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.settled,
      ));
    }

    test('rejects duplicate SKU on create without writing', () async {
      await seedProduct('p1', sku: 'DUP-1');
      await expectLater(
        repository.createProduct(const ProductDraft(
          name: 'Duplicate',
          sku: 'DUP-1',
          costPrice: 1,
          sellingPrice: 2,
          locationId: locationId,
        )),
        throwsArgumentError,
      );
      expect(await db.select(db.products).get(), hasLength(1));
      expect(await db.select(db.syncQueueItems).get(), isEmpty);
    });

    test('rejects duplicate barcode on create without writing', () async {
      await seedProduct('p1', sku: 'SKU-1', barcode: '123');
      await expectLater(
        repository.createProduct(const ProductDraft(
          name: 'Duplicate',
          sku: 'SKU-2',
          barcode: '123',
          costPrice: 1,
          sellingPrice: 2,
          locationId: locationId,
        )),
        throwsArgumentError,
      );
      expect(await db.select(db.products).get(), hasLength(1));
    });

    test('archives a product locally and queues one update', () async {
      await seedProduct('p1');
      await repository.archiveProduct('p1');
      final row = await (db.select(db.products)..where((p) => p.localId.equals('p1'))).getSingle();
      expect(row.isActive, false);
      expect(row.deletedAt, isNotNull);
      expect(row.syncStatus, SyncStatus.pending);
      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.operation, 'update');
    });
  });

}
