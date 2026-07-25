import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/remote/endpoints/income_api.dart';
import 'package:bms_mobile/data/repositories/income_record_repository_impl.dart';
import 'package:bms_mobile/domain/entities/income_record.dart';
import 'package:bms_mobile/sync/handlers/income_sync_handler.dart';
import 'package:bms_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockIncomeApi extends Mock implements IncomeApi {}

void main() {
  late AppDatabase db;
  late MockIncomeApi incomeApi;
  late IncomeRecordRepositoryImpl incomeRecordRepository;
  late IncomeSyncHandler handler;

  setUpAll(() {
    registerFallbackValue(
      IncomeCreateDto(
        source: 'fallback',
        amount: 0,
        incomeDate: DateTime(2020),
      ),
    );
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    incomeApi = MockIncomeApi();
    incomeRecordRepository = IncomeRecordRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = IncomeSyncHandler(
      incomeApi: incomeApi,
      incomeRecordRepository: incomeRecordRepository,
    );
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

  test(
      'sends the client_reference equal to the local id and marks the '
      'local income record synced from the response', () async {
    final record = await incomeRecordRepository.recordIncome(
      IncomeRecordDraft(source: 'Equipment rental', amount: 15000, incomeDate: DateTime(2026, 7, 1)),
    );

    when(() => incomeApi.createIncome(any())).thenAnswer(
      (_) async => IncomeRecord(
        localId: record.localId,
        serverId: 'server-income-1',
        source: record.source,
        amount: record.amount,
        incomeDate: record.incomeDate,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(record));

    final captured = verify(() => incomeApi.createIncome(captureAny())).captured;
    final dto = captured.single as IncomeCreateDto;
    expect(dto.clientReference, record.localId);
    expect(dto.source, 'Equipment rental');

    final updated = await incomeRecordRepository.getIncomeRecordById(record.localId);
    expect(updated!.serverId, 'server-income-1');
  });

  test('throws for an operation other than create', () async {
    final record = await incomeRecordRepository.recordIncome(
      IncomeRecordDraft(source: 'Fuel refund', amount: 3000, incomeDate: DateTime(2026, 7, 1)),
    );

    await expectLater(
      handler.sync(queueItemFor(record, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    final phantomItem = SyncQueueItem(
      id: 'q1',
      entityType: 'income_record',
      entityLocalId: 'never-existed',
      operation: 'create',
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );

    await expectLater(
      handler.sync(phantomItem),
      throwsA(isA<StateError>()),
    );
  });
}
