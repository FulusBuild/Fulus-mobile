import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/endpoints/products_api.dart';
import 'package:fulus_mobile/data/remote/endpoints/stock_movements_api.dart';
import 'package:fulus_mobile/data/repositories/product_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/stock_movement_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/domain/entities/stock_movement.dart';
import 'package:fulus_mobile/sync/handlers/stock_movement_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockStockMovementsApi extends Mock implements StockMovementsApi {}

// Never stubbed/verified in any test below — ProductRepositoryImpl's
// constructor requires a ProductsApi, but reconcileStockLevel (the only
// method these tests exercise) never calls it. A real ProductRepositoryImpl
// is used instead of a mocked ProductRepository specifically so these
// tests exercise the actual reconciliation write, not just verify it was
// "called" — the same "real in-memory Drift, no mocks where the network
// isn't involved" preference every other repository test in this suite
// already follows.
class MockProductsApi extends Mock implements ProductsApi {}

void main() {
  late AppDatabase db;
  late MockStockMovementsApi stockMovementsApi;
  late StockMovementRepositoryImpl stockMovementRepository;
  late ProductRepositoryImpl productRepository;
  late StockMovementSyncHandler handler;

  const locationId = 'loc-1';
  const productLocalId = 'prod-1';
  const productServerId = 'server-prod-1';

  ProductResponseDto fakeProductResponse({required int currentStock}) => ProductResponseDto(
        id: productServerId,
        name: 'USB-C Cable',
        sku: 'CAB-USBC',
        costPrice: 500.0,
        sellingPrice: 1200.0,
        lowStockThreshold: 10,
        currentStock: currentStock,
        isActive: true,
        isLowStock: false,
        stockValue: 500.0 * currentStock,
      );

  setUpAll(() {
    registerFallbackValue(const StockInCreateDto(quantity: 1, locationId: locationId));
    registerFallbackValue(const StockOutCreateDto(quantity: 1, locationId: locationId));
    registerFallbackValue(const StockAdjustmentCreateDto(newQuantity: 1, reason: 'fallback', locationId: locationId));
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    stockMovementsApi = MockStockMovementsApi();
    stockMovementRepository = StockMovementRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    productRepository = ProductRepositoryImpl(db: db, productsApi: MockProductsApi());
    handler = StockMovementSyncHandler(
      db: db,
      stockMovementsApi: stockMovementsApi,
      stockMovementRepository: stockMovementRepository,
      productRepository: productRepository,
    );

    await db.into(db.locations).insert(LocationsCompanion.insert(
          localId: locationId,
          name: 'Main Store',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.settled,
        ));
  });

  tearDown(() async {
    await db.close();
  });

  SyncQueueItem queueItemFor(String entityLocalId, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'stock_movement',
      entityLocalId: entityLocalId,
      operation: operation,
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  group('with a product that has a serverId', () {
    setUp(() async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            localId: productLocalId,
            name: 'USB-C Cable',
            sku: 'CAB-USBC',
            costPrice: 500.0,
            sellingPrice: 1200.0,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
            syncStatus: SyncStatus.settled,
            serverId: const Value(productServerId),
          ));
    });

    test('stockIn: calls the stock-in endpoint with the product serverId and marks settled', () async {
      final movement = await stockMovementRepository.recordStockIn(
        const StockInDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          quantity: 20,
          reason: 'New delivery',
        ),
      );

      when(() => stockMovementsApi.stockIn(
            productId: any(named: 'productId'),
            dto: any(named: 'dto'),
          )).thenAnswer((_) async => fakeProductResponse(currentStock: 45));

      await handler.sync(queueItemFor(movement.localId));

      final captured = verify(() => stockMovementsApi.stockIn(
            productId: captureAny(named: 'productId'),
            dto: captureAny(named: 'dto'),
          )).captured;
      expect(captured[0], productServerId);
      final dto = captured[1] as StockInCreateDto;
      expect(dto.quantity, 20);
      expect(dto.reason, 'New delivery');
      expect(dto.clientReference, movement.localId);

      final updated = await stockMovementRepository.getStockMovementById(movement.localId);
      expect(updated!.serverId, isNull);
    });

    test('stockOut: calls the stock-out endpoint with the product serverId', () async {
      final movement = await stockMovementRepository.recordStockOut(
        const StockOutDraft(productLocalId: productLocalId, locationId: locationId, quantity: 5),
      );

      when(() => stockMovementsApi.stockOut(
            productId: any(named: 'productId'),
            dto: any(named: 'dto'),
          )).thenAnswer((_) async => fakeProductResponse(currentStock: 15));

      await handler.sync(queueItemFor(movement.localId));

      final captured = verify(() => stockMovementsApi.stockOut(
            productId: captureAny(named: 'productId'),
            dto: captureAny(named: 'dto'),
          )).captured;
      expect(captured[0], productServerId);
      final dto = captured[1] as StockOutCreateDto;
      expect(dto.quantity, 5);
      expect(dto.clientReference, movement.localId);
    });

    test('adjustment: calls the adjust-stock endpoint with newQuantity and required reason', () async {
      final movement = await stockMovementRepository.recordAdjustment(
        const StockAdjustmentDraft(
          productLocalId: productLocalId,
          locationId: locationId,
          newQuantity: 42,
          reason: 'Recount',
        ),
      );

      when(() => stockMovementsApi.adjustStock(
            productId: any(named: 'productId'),
            dto: any(named: 'dto'),
          )).thenAnswer((_) async => fakeProductResponse(currentStock: 42));

      await handler.sync(queueItemFor(movement.localId));

      final captured = verify(() => stockMovementsApi.adjustStock(
            productId: captureAny(named: 'productId'),
            dto: captureAny(named: 'dto'),
          )).captured;
      expect(captured[0], productServerId);
      final dto = captured[1] as StockAdjustmentCreateDto;
      expect(dto.newQuantity, 42);
      expect(dto.reason, 'Recount');
      expect(dto.clientReference, movement.localId);
    });

    test('marks the local movement settled after a successful sync', () async {
      final movement = await stockMovementRepository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      when(() => stockMovementsApi.stockIn(
            productId: any(named: 'productId'),
            dto: any(named: 'dto'),
          )).thenAnswer((_) async => fakeProductResponse(currentStock: 45));

      await handler.sync(queueItemFor(movement.localId));

      final row = await (db.select(db.stockMovements)
            ..where((m) => m.localId.equals(movement.localId)))
          .getSingle();
      expect(row.syncStatus, SyncStatus.settled);
    });

    test('reconciles ProductStockLevels with the response currentStock — the whole point of item 2', () async {
      final movement = await stockMovementRepository.recordStockIn(
        const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
      );

      when(() => stockMovementsApi.stockIn(
            productId: any(named: 'productId'),
            dto: any(named: 'dto'),
          )).thenAnswer((_) async => fakeProductResponse(currentStock: 45));

      await handler.sync(queueItemFor(movement.localId));

      final stockLevel = await (db.select(db.productStockLevels)
            ..where((s) =>
                s.productLocalId.equals(productLocalId) & s.locationLocalId.equals(locationId)))
          .getSingle();
      expect(stockLevel.currentStock, 45);
      expect(stockLevel.syncStatus, SyncStatus.settled);
    });
  });

  test('throws when the product has no serverId yet', () async {
    // Deliberately no serverId set here. Should be unreachable in
    // practice now that Products only ever gets rows from a real synced
    // product (see StockMovementSyncHandler's own comment) — this test
    // exercises the defensive check directly, not a realistic scenario.
    await db.into(db.products).insert(ProductsCompanion.insert(
          localId: productLocalId,
          name: 'USB-C Cable',
          sku: 'CAB-USBC',
          costPrice: 500.0,
          sellingPrice: 1200.0,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          syncStatus: SyncStatus.pending,
        ));
    final movement = await stockMovementRepository.recordStockIn(
      const StockInDraft(productLocalId: productLocalId, locationId: locationId, quantity: 20),
    );

    await expectLater(
      handler.sync(queueItemFor(movement.localId)),
      throwsA(isA<StateError>()),
    );
  });

  test('throws for an operation other than create', () async {
    await expectLater(
      handler.sync(queueItemFor('whatever-id', operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    await expectLater(
      handler.sync(queueItemFor('never-existed')),
      throwsA(isA<StateError>()),
    );
  });
}
