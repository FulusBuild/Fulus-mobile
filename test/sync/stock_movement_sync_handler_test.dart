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

  SyncQueueItem itemFor(String localId, {String operation = 'create'}) => SyncQueueItem(
    id: 'q1', entityType: 'stock_movement', entityLocalId: localId, operation: operation,
    priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
  );

  test('pushes stock-in through Fulus Cloud and reconciles returned stock', () async {
    final movement = await stockMovementRepository.recordStockIn(const StockInDraft(
      productLocalId: productLocalId, locationId: locationId, quantity: 20, reason: 'New delivery',
    ));
    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-movement-1', 'current_stock': 45}});
    await handler.sync(itemFor(movement.localId));
    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1', operationType: 'stock_movement.create', operationId: 'q1', deviceClientId: 'device-client-1',
      clientReference: movement.localId, payload: any(named: 'payload'),
    )).called(1);
    verify(() => productRepository.reconcileStockLevel(productLocalId: productLocalId, locationId: locationId, currentStock: 45)).called(1);
    final row = await stockMovementRepository.getStockMovementById(movement.localId);
    expect(row!.serverId, isNull);
    final stored = await (db.select(db.stockMovements)..where((m) => m.localId.equals(movement.localId))).getSingle();
    expect(stored.syncStatus, SyncStatus.settled);
  });

  test('rejects adjustments instead of inventing a delta', () async {
    final movement = await stockMovementRepository.recordAdjustment(const StockAdjustmentDraft(
      productLocalId: productLocalId, locationId: locationId, newQuantity: 42, reason: 'Recount',
    ));
    await expectLater(handler.sync(itemFor(movement.localId)), throwsA(isA<StateError>()));
    verifyNever(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'), operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'), clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    ));
  });

  test('throws for an operation other than create', () async {
    await expectLater(handler.sync(itemFor('whatever', operation: 'update')), throwsA(isA<StateError>()));
  });

  test('throws when the queue item has outlived its local row', () async {
    await expectLater(handler.sync(itemFor('never-existed')), throwsA(isA<StateError>()));
  });
}
