import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/return_request.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/domain/repositories/return_repository.dart';
import 'package:fulus_mobile/sync/handlers/return_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:mocktail/mocktail.dart';

class _MockFulusSyncApi extends Mock implements FulusSyncApi {}
class _MockConnectionState extends Mock implements FulusConnectionState {}
class _MockReturnRepository extends Mock implements ReturnRepository {}
class _MockProductRepository extends Mock implements ProductRepository {}
class _MockCustomerRepository extends Mock implements CustomerRepository {}

void main() {
  test('permanent rejection stays reconciliation-pending when canonical fetch fails', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime(2026, 11, 20);
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-local',
      name: 'Test location',
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
    ));
    await db.into(db.products).insert(ProductsCompanion.insert(
      localId: 'product-local',
      locationId: const Value('location-local'),
      name: 'Test product',
      sku: 'TEST-1',
      costPrice: 100,
      sellingPrice: 200,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
      serverId: const Value('product-server'),
    ));
    await db.into(db.sales).insert(SalesCompanion.insert(
      localId: 'sale-local',
      clientReference: 'sale-reference',
      locationId: 'location-local',
      saleDate: now,
      subtotal: 200,
      total: 200,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
      serverId: const Value('sale-server'),
    ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
      localId: 'sale-line-local',
      saleLocalId: 'sale-local',
      productLocalId: const Value('product-local'),
      quantity: 1,
      unitPrice: 200,
      costPriceAtSale: 100,
    ));
    await db.into(db.returnRequests).insert(ReturnRequestsCompanion.insert(
      localId: 'return-local',
      originalSaleLocalId: 'sale-local',
      status: 'completed',
      returnReason: 'Customer return',
      refundAmount: 200,
      refundMethod: 'cash',
      inventoryRestored: const Value(true),
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    ));
    await db.into(db.returnItems).insert(ReturnItemsCompanion.insert(
      localId: 'return-line-local',
      returnLocalId: 'return-local',
      productLocalId: 'product-local',
      quantity: 1,
    ));
    await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
      id: 'return-operation',
      entityType: 'return',
      entityLocalId: 'return-local',
      operation: 'create',
      priority: 1,
      enqueuedAt: now,
    ));

    final request = ReturnRequest(
      localId: 'return-local',
      originalSaleLocalId: 'sale-local',
      status: ReturnStatus.completed,
      returnReason: 'Customer return',
      refundAmount: 200,
      refundMethod: 'cash',
      inventoryRestored: true,
      items: const [ReturnItem(
        localId: 'return-line-local',
        returnLocalId: 'return-local',
        productLocalId: 'product-local',
        quantity: 1,
      )],
      createdAt: now,
      updatedAt: now,
    );
    final syncApi = _MockFulusSyncApi();
    final connectionState = _MockConnectionState();
    final returnRepository = _MockReturnRepository();
    final productRepository = _MockProductRepository();
    final customerRepository = _MockCustomerRepository();
    final executionLease = SyncExecutionLease(db);

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-server',
        businessId: 'business-1',
        deviceClientId: 'device-client',
        status: 'active',
      ),
    );
    when(() => returnRepository.getReturnById('return-local', forSync: true))
        .thenAnswer((_) async => request);
    when(() => returnRepository.markReconciliationPending(localId: 'return-local'))
        .thenAnswer((_) async {});
    when(() => returnRepository.markRejected(localId: 'return-local'))
        .thenAnswer((_) async {});
    when(() => syncApi.submitOperation(
      businessId: any(named: 'businessId'),
      operationType: any(named: 'operationType'),
      operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'),
      clientReference: any(named: 'clientReference'),
      payload: any(named: 'payload'),
    )).thenThrow(const BusinessRuleFailure('Return rejected'));
    when(() => syncApi.fetchCanonicalEntity(
      businessId: any(named: 'businessId'),
      entityType: any(named: 'entityType'),
      entityId: any(named: 'entityId'),
      deviceClientId: any(named: 'deviceClientId'),
    )).thenThrow(StateError('Canonical state is unavailable'));

    final handler = ReturnSyncHandler(
      db: db,
      fulusSyncApi: syncApi,
      executionLease: executionLease,
      fulusConnectionState: connectionState,
      returnRepository: returnRepository,
      productRepository: productRepository,
      customerRepository: customerRepository,
    );
    final queueItem = await (db.select(db.syncQueueItems)
          ..where((row) => row.id.equals('return-operation')))
        .getSingle();

    await expectLater(handler.sync(queueItem), throwsA(isA<BusinessRuleFailure>()));
    verify(() => returnRepository.markReconciliationPending(localId: 'return-local'))
        .called(1);
    verifyNever(() => returnRepository.markRejected(localId: 'return-local'));
  });
}
