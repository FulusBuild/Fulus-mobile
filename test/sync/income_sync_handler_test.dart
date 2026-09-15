import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/income_record_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/income_record.dart';
import 'package:fulus_mobile/sync/handlers/income_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late IncomeRecordRepositoryImpl incomeRecordRepository;
  late IncomeSyncHandler handler;

  const locationId = 'loc-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    incomeRecordRepository = IncomeRecordRepositoryImpl(
      db: db,
      syncQueue: SyncQueue(db),
    );
    handler = IncomeSyncHandler(
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
      incomeRecordRepository: incomeRecordRepository,
    );
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));
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

  SyncQueueItem queueItemFor(IncomeRecord record, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'income_record',
      entityLocalId: record.localId,
      operation: operation,
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  test('pushes income through Fulus Cloud and marks it synced', () async {
    final record = await incomeRecordRepository.recordIncome(
      const IncomeRecordDraft(
        locationId: locationId,
        source: 'Equipment rental',
        amount: 15000,
        incomeDate: DateTime(2026, 7, 1),
      ),
    );

    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
          'data': {'entity_id': 'server-income-1'},
        });

    await handler.sync(queueItemFor(record));

    verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'income.create',
          operationId: 'q1',
          deviceClientId: 'device-client-1',
          clientReference: record.localId,
          payload: any(named: 'payload'),
        )).called(1);

    final updated = await incomeRecordRepository.getIncomeRecordById(record.localId);
    expect(updated!.serverId, 'server-income-1');
  });

  test('throws for an operation other than create', () async {
    final record = await incomeRecordRepository.recordIncome(
      const IncomeRecordDraft(
        locationId: locationId,
        source: 'Fuel refund',
        amount: 3000,
        incomeDate: DateTime(2026, 7, 1),
      ),
    );

    await expectLater(
      handler.sync(queueItemFor(record, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    await expectLater(
      handler.sync(SyncQueueItem(
        id: 'q1',
        entityType: 'income_record',
        entityLocalId: 'never-existed',
        operation: 'create',
        priority: 1,
        enqueuedAt: DateTime.now(),
        syncAttempts: 0,
      )),
      throwsA(isA<StateError>()),
    );
  });
}
