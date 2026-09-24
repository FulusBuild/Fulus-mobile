import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/category.dart';
import 'package:fulus_mobile/domain/repositories/category_repository.dart';
import 'package:fulus_mobile/sync/handlers/category_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockCategoryRepository extends Mock implements CategoryRepository {}

void main() {
  late MockFulusSyncApi api;
  late MockFulusConnectionState connectionState;
  late MockCategoryRepository categoryRepository;
  late CategorySyncHandler handler;

  setUp(() {
    api = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    categoryRepository = MockCategoryRepository();
    handler = CategorySyncHandler(
      categoryRepository: categoryRepository,
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
    when(() => categoryRepository.markSynced(
          localId: any(named: 'localId'),
          serverId: any(named: 'serverId'),
        )).thenAnswer((_) async {});
  });

  test('archived never-synced category uses the create change sequence for delete OCC',
      () async {
    final now = DateTime(2026, 9, 24);
    final category = Category(
      localId: 'c-pre-sync',
      name: 'Archived Category',
      description: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: now,
    );
    final queueItem = SyncQueueItem(
      id: 'queue-category-create',
      entityType: 'category',
      entityLocalId: 'c-pre-sync',
      operation: 'create',
      priority: 0,
      enqueuedAt: now,
      baseCursor: 10,
    );

    when(() => categoryRepository.getCategoryById('c-pre-sync'))
        .thenAnswer((_) async => category);
    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((invocation) async {
      final operationType =
          invocation.namedArguments[#operationType] as String;
      if (operationType == 'category.create') {
        return {
          'data': {
            'entity_id': 'server-category-1',
            'sync_sequence': 11,
          },
        };
      }
      if (operationType == 'category.delete') {
        final payload =
            invocation.namedArguments[#payload] as Map<String, dynamic>;
        expect(payload['server_id'], 'server-category-1');
        expect(payload['base_cursor'], 11);
        return {
          'data': {
            'entity_id': 'server-category-1',
            'status': 'deleted',
          },
        };
      }
      throw StateError('Unexpected operation type: $operationType');
    });

    await handler.sync(queueItem);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'category.create',
          operationId: 'queue-category-create',
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);
    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'category.delete',
          operationId: 'queue-category-create:delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-category-1',
            'base_cursor': 11,
          },
        )).called(1);
  });
}
