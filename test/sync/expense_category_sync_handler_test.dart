import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/expense_category_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/expense_category.dart';
import 'package:fulus_mobile/sync/handlers/expense_category_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi api;
  late MockFulusConnectionState connection;
  late ExpenseCategoryRepositoryImpl repository;
  late ExpenseCategorySyncHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = MockFulusSyncApi();
    connection = MockFulusConnectionState();
    repository = ExpenseCategoryRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
    );
    handler = ExpenseCategorySyncHandler(
      fulusSyncApi: api,
      fulusConnectionState: connection,
      expenseCategoryRepository: repository,
    );
    when(() => connection.selectedBusinessId).thenReturn('business-1');
    when(() => connection.registeredDevice).thenReturn(
      const FulusRegisteredDevice(
        id: 'device-1',
        businessId: 'business-1',
        deviceClientId: 'device-client-1',
        status: 'active',
      ),
    );
  });

  tearDown(() => db.close());

  test('pushes an expense category through the cloud contract', () async {
    final category = await repository.createExpenseCategory(
      const ExpenseCategoryDraft(name: 'Utilities'),
    );

    when(() => api.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer(
      (_) async => {'data': {'entity_id': 'server-category-1'}},
    );

    final queueItem = await (db.select(db.syncQueueItems)
          ..where((q) => q.entityLocalId.equals(category.localId)))
        .getSingle();

    await handler.sync(queueItem);

    verify(() => api.submitOperation(
          businessId: 'business-1',
          operationType: 'expense_category.create',
          operationId: category.localId,
          deviceClientId: 'device-client-1',
          payload: any(named: 'payload'),
        )).called(1);

    expect(
      (await repository.getExpenseCategoryById(category.localId))!.serverId,
      'server-category-1',
    );
  });
}
