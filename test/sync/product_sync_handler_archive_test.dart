import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/sync/handlers/product_sync_handler.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi api;
  late MockFulusConnectionState connectionState;
  late MockProductRepository productRepository;
  late ProductSyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    productRepository = MockProductRepository();
    handler = ProductSyncHandler(
      productRepository: productRepository,
      db: db,
      fulusSyncApi: api,
      fulusConnectionState: connectionState,
    );

    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
    when(() => productRepository.markSynced(
          localId: any(named: 'localId'),
          serverId: any(named: 'serverId'),
          operationId: any(named: 'operationId'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async => db.close());

  test('creates then archives a pre-sync product without reusing the stale create cursor', () async {
    final now = DateTime(2026, 9, 22);
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'p-pre-sync',
        name: 'Archived before cloud',
        sku: 'ARCHIVE-PRE-1',
        costPrice: 10,
        sellingPrice: 20,
        isActive: const Value(false),
        deletedAt: Value(now),
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'queue-product-create',
        entityType: 'product',
        entityLocalId: 'p-pre-sync',
        operation: 'create',
        priority: 0,
        enqueuedAt: now,
        baseCursor: const Value(10),
      ),
    );

    var call = 0;
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      call++;
      if (call == 1) {
        return {
          'data': {'entity_id': 'server-pre-sync', 'sync_sequence': 11},
        };
      }
      return {
        'data': {'entity_id': 'server-pre-sync', 'status': 'deleted'},
      };
    });

    final item = await db.select(db.syncQueueItems).getSingle();
    await handler.sync(item);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.create',
          operationId: 'queue-product-create',
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);
    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.delete',
          operationId: 'queue-product-create:delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-pre-sync',
            'base_cursor': 11,
          },
        )).called(1);
  });

  test('archives an already-synced product through catalog.delete', () async {
    final now = DateTime(2026, 9, 22);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: 'p1',
            serverId: const Value('server-product-1'),
            name: 'Archived product',
            sku: 'ARCHIVE-1',
            costPrice: 10,
            sellingPrice: 20,
            isActive: const Value(false),
            deletedAt: Value(now),
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          ),
        );

    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: 'queue-product-delete',
            entityType: 'product',
            entityLocalId: 'p1',
            operation: 'update',
            priority: 0,
            enqueuedAt: now,
          ),
        );

    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer(
      (_) async => {
        'data': {
          'entity_id': 'server-product-1',
          'status': 'deleted',
        },
      },
    );

    final item = await db.select(db.syncQueueItems).getSingle();
    await handler.sync(item);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'product.delete',
          operationId: 'queue-product-delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-product-1',
          },
        )).called(1);
    verify(() => productRepository.markSynced(
          localId: 'p1',
          serverId: 'server-product-1',
          operationId: 'queue-product-delete',
        )).called(1);
  });
}
