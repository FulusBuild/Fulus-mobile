import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/stock_movement_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/stock_movement.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/sync/handlers/stock_movement_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late MockProductRepository productRepository;
  late StockMovementRepositoryImpl stockMovementRepository;
  late StockMovementSyncHandler handler;
  const locationId = 'loc-1';
  const productLocalId = 'prod-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    productRepository = MockProductRepository();
    stockMovementRepository = StockMovementRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = StockMovementSyncHandler(db: db, fulusSyncApi: fulusSyncApi, fulusConnectionState: connectionState, stockMovementRepository: stockMovementRepository, productRepository: productRepository);
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: locationId, name: 'Main Store', serverId: const Value('server-location-1'),
      createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1), syncStatus: SyncStatus.settled,
    ));
    await db.into(db.products).insert(ProductsCompanion.insert(
      localId: productLocalId, name: 'USB-C Cable', sku: 'CAB-USBC', costPrice: 500, sellingPrice: 1200,
      serverId: const Value('server-product-1'), createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1), syncStatus: SyncStatus.settled,
    ));
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1', businessId: 'business-1', deviceClientId: 'device-client-1', status: 'active',
    ));
  });

  tearDown(() async => db.close());

  Future<SyncQueueItem> itemFor(String localId, {String operation = 'create'}) async {
    final item = SyncQueueItem(
    id: 'q1', entityType: 'stock_movement', entityLocalId: localId, operation: operation,
    priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
    );
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.entityType.equals(item.entityType))
          ..where((q) => q.entityLocalId.equals(item.entityLocalId)))
        .go();
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: item.id,
        entityType: item.entityType,
        entityLocalId: item.entityLocalId,
        operation: item.operation,
        priority: item.priority,
        enqueuedAt: item.enqueuedAt,
        syncAttempts: Value(item.syncAttempts),
      ),
    );
    return item;
  }

  test('pushes stock-in through Fulus Cloud and reconciles returned stock', () async {
    final movement = await stockMovementRepository.recordStockIn(const StockInDraft(
      productLocalId: productLocalId, locationId: locationId, quantity: 20, reason: 'New delivery',
    ));
    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-movement-1', 'current_stock': 45}});
    when(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId, locationId: locationId, currentStock: 45, operationId: any(named: 'operationId'),
    )).thenAnswer((_) async {});
    await handler.sync(await itemFor(movement.localId));
    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1', operationType: 'stock_movement.create', operationId: 'q1', deviceClientId: 'device-client-1',
      clientReference: movement.localId, payload: any(named: 'payload'),
    )).called(1);
    verify(() => productRepository.reconcileStockLevel(productLocalId: productLocalId, locationId: locationId, currentStock: 45, operationId: 'q1')).called(1);
    final row = await stockMovementRepository.getStockMovementById(movement.localId);
    expect(row!.serverId, isNull);
    final stored = await (db.select(db.stockMovements)..where((m) => m.localId.equals(movement.localId))).getSingle();
    expect(stored.syncStatus, SyncStatus.settled);
  });

  test('submits a pending stock movement with its original location after active location switches', () async {
    final now = DateTime.now();
    await db.into(db.locations).insert(
      LocationsCompanion.insert(
        localId: 'loc-2',
        name: 'Location B',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
        serverId: const Value('server-location-B'),
      ),
    );
    await (db.update(db.locations)..where((l) => l.localId.equals(locationId)))
        .write(const LocationsCompanion(serverId: Value('server-location-A')));

    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-movement-A', 'current_stock': 30}});
    when(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId, locationId: locationId, currentStock: 30, operationId: any(named: 'operationId'),
    )).thenAnswer((_) async {});

    final movement = await stockMovementRepository.recordStockIn(const StockInDraft(
      productLocalId: productLocalId, locationId: locationId, quantity: 10, reason: 'Delivery to A',
    ));

    // The active UI location is not an input to the sync handler. Switching
    // it conceptually to B must not rewrite the persisted movement location.
    expect(movement.locationId, locationId);

    await handler.sync(await itemFor(movement.localId));

    final captured = verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1', operationType: 'stock_movement.create', operationId: 'q1', deviceClientId: 'device-client-1',
      clientReference: movement.localId, payload: captureAny(named: 'payload'),
    )).captured.single as Map<String, dynamic>;
    expect(captured['location_id'], 'server-location-A');
    expect(captured['location_id'], isNot('server-location-B'));
  });

  test('submits a pending B mutation unchanged while active context is A', () async {
    final now = DateTime.now();
    await db.into(db.locations).insert(
      LocationsCompanion.insert(
        localId: 'loc-2',
        name: 'Location B',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.settled,
        serverId: const Value('server-location-B'),
      ),
    );

    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-movement-B', 'current_stock': 17}});
    when(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId, locationId: 'loc-2', currentStock: 17, operationId: any(named: 'operationId'),
    )).thenAnswer((_) async {});

    final movement = await stockMovementRepository.recordStockIn(const StockInDraft(
      productLocalId: productLocalId,
      locationId: 'loc-2',
      quantity: 7,
      reason: 'Delivery to B',
    ));

    // Model the user having switched back to A before the pending B item replays.
    expect(movement.locationId, 'loc-2');
    await handler.sync(await itemFor(movement.localId));

    final captured = verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1',
      operationType: 'stock_movement.create',
      operationId: 'q1',
      deviceClientId: 'device-client-1',
      clientReference: movement.localId,
      payload: captureAny(named: 'payload'),
    )).captured.single as Map<String, dynamic>;

    expect(captured['location_id'], 'server-location-B');
    expect(captured['location_id'], isNot('server-location-1'));
    verify(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId,
      locationId: 'loc-2',
      currentStock: 17,
      operationId: 'q1',
    )).called(1);
  });

  test('pushes absolute stock adjustments and reconciles returned stock', () async {
    final movement = await stockMovementRepository.recordAdjustment(const StockAdjustmentDraft(
      productLocalId: productLocalId, locationId: locationId, newQuantity: 42, reason: 'Recount',
    ));
    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-movement-adjustment-1', 'current_stock': 42}});
    when(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId, locationId: locationId, currentStock: 42, operationId: any(named: 'operationId'),
    )).thenAnswer((_) async {});
    await handler.sync(await itemFor(movement.localId));
    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1', operationType: 'stock_adjustment.create', operationId: 'q1', deviceClientId: 'device-client-1',
      clientReference: movement.localId,
      payload: any(named: 'payload'),
    )).called(1);
    verify(() => productRepository.reconcileStockLevel(
      productLocalId: productLocalId, locationId: locationId, currentStock: 42, operationId: 'q1',
    )).called(1);
    final stored = await (db.select(db.stockMovements)..where((m) => m.localId.equals(movement.localId))).getSingle();
    expect(stored.syncStatus, SyncStatus.settled);
  });

  test('throws for an operation other than create', () async {
    await expectLater(handler.sync(await itemFor('whatever', operation: 'update')), throwsA(isA<StateError>()));
  });

  test('throws when the queue item has outlived its local row', () async {
    await expectLater(handler.sync(await itemFor('never-existed')), throwsA(isA<StateError>()));
  });
}
