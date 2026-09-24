import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/repositories/audit_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/expense_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/expense.dart';
import 'package:fulus_mobile/sync/handlers/expense_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}

void main() {
  late AppDatabase db;
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late ExpenseRepositoryImpl expenseRepository;
  late ExpenseSyncHandler handler;
  late SyncExecutionLease executionLease;
  const locationId = 'loc-1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    executionLease = SyncExecutionLease(db);
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    final audit = AuditRepositoryImpl(db: db);
    expenseRepository = ExpenseRepositoryImpl(db: db, syncQueue: SyncQueue(db), auditRepository: audit);
    handler = ExpenseSyncHandler(db: db, fulusSyncApi: fulusSyncApi, fulusConnectionState: connectionState, expenseRepository: expenseRepository, executionLease: executionLease);
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: locationId, name: 'Main Store', serverId: const Value('server-location-1'),
      createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1), syncStatus: SyncStatus.settled,
    ));
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(FulusRegisteredDevice(
      id: 'device-1', businessId: 'business-1', deviceClientId: 'device-client-1', status: 'active',
    ));
  });

  tearDown(() async {
    await executionLease.release();
    await db.close();
  });

  SyncQueueItem itemFor(Expense expense, {String operation = 'create'}) => SyncQueueItem(
    id: 'q1', entityType: 'expense', entityLocalId: expense.localId, operation: operation,
    priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
  );

  test('pushes an expense through Fulus Cloud and marks it synced', () async {
    final expense = await expenseRepository.recordExpense(ExpenseDraft(
      locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1),
    ));
    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'), operationType: any(named: 'operationType'),
      operationId: any(named: 'operationId'), deviceClientId: any(named: 'deviceClientId'),
      clientReference: any(named: 'clientReference'), payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-expense-1'}});
    await handler.sync(itemFor(expense));
    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1', operationType: 'expense.create', operationId: 'q1',
      deviceClientId: 'device-client-1', clientReference: expense.localId, payload: any(named: 'payload'),
    )).called(1);
    final updated = await expenseRepository.getExpenseById(expense.localId);
    expect(updated!.serverId, 'server-expense-1');
  });

  test('pushes an expense update through Fulus Cloud', () async {
    final expense = await expenseRepository.recordExpense(ExpenseDraft(
      locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1),
    ));
    await expenseRepository.markSynced(
      localId: expense.localId,
      serverId: 'server-expense-1',
    );
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.entityLocalId.equals(expense.localId)))
        .go();
    final updated = await expenseRepository.updateExpense(
      localId: expense.localId,
      description: 'Generator fuel',
      amount: 4500,
      expenseDate: DateTime(2026, 7, 2),
    );

    when(() => fulusSyncApi.submitOperation(
      businessId: any(named: 'businessId'),
      operationType: any(named: 'operationType'),
      operationId: any(named: 'operationId'),
      deviceClientId: any(named: 'deviceClientId'),
      clientReference: any(named: 'clientReference'),
      payload: any(named: 'payload'),
    )).thenAnswer((_) async => {'data': {'entity_id': 'server-expense-1'}});

    await handler.sync(itemFor(updated, operation: 'update'));

    verify(() => fulusSyncApi.submitOperation(
      businessId: 'business-1',
      operationType: 'expense.update',
      operationId: 'q1',
      deviceClientId: 'device-client-1',
      clientReference: updated.localId,
      payload: any(named: 'payload'),
    )).called(1);
  });

  test('throws when the queue item has outlived its local row', () async {
    await expectLater(handler.sync(SyncQueueItem(
      id: 'q1', entityType: 'expense', entityLocalId: 'never-existed', operation: 'create',
      priority: 1, enqueuedAt: DateTime.now(), syncAttempts: 0,
    )), throwsA(isA<StateError>()));
  });
}
