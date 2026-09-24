import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/category_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/category.dart';
import 'package:fulus_mobile/sync/handlers/category_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi api;
  late MockFulusConnectionState connectionState;
  late CategoryRepositoryImpl categoryRepository;
  late CategorySyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    categoryRepository = CategoryRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
    );
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
  });

  tearDown(() async => db.close());

  test('archived never-synced category uses the create change sequence for delete OCC',
      () async {
    final created = await categoryRepository.createCategory(
      const CategoryDraft(name: 'Archived Category'),
    );
    await categoryRepository.archiveCategory(created.localId);

    final queued = await (db.select(db.syncQueueItems)
          ..where((q) => q.entityType.equals('category'))
          ..where((q) => q.entityLocalId.equals(created.localId))
          ..where((q) => q.operation.equals('create')))
        .getSingle();

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
            'entity_id': 'server-archived-category',
            'sync_sequence': 31,
          },
        };
      }
      if (operationType == 'category.delete') {
        final payload =
            invocation.namedArguments[#payload] as Map<String, dynamic>;
        expect(payload['server_id'], 'server-archived-category');
        expect(payload['base_cursor'], 31);
        return {
          'data': {
            'entity_id': 'server-archived-category',
            'status': 'deleted',
          },
        };
      }
      throw StateError('Unexpected operation type: ' + operationType);
    });

    await handler.sync(queued);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'category.create',
          operationId: queued.id,
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);
    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'category.delete',
          operationId: queued.id + ':delete',
          deviceClientId: 'device-client-1',
          payload: {
            'server_id': 'server-archived-category',
            'base_cursor': 31,
          },
        )).called(1);

    final settled = await categoryRepository.getCategoryById(created.localId);
    expect(settled!.serverId, 'server-archived-category');
  });
}
