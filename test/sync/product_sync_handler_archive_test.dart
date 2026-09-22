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
        )).thenAnswer((_) async {});
  });

  tearDown(() async => db.close());

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
        )).called(1);
  });
}
