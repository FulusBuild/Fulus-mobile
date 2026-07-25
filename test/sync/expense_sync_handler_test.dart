import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/local/database/tables.dart';
import 'package:bms_mobile/data/remote/endpoints/expenses_api.dart';
import 'package:bms_mobile/data/repositories/expense_repository_impl.dart';
import 'package:bms_mobile/domain/entities/expense.dart';
import 'package:bms_mobile/sync/handlers/expense_sync_handler.dart';
import 'package:bms_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockExpensesApi extends Mock implements ExpensesApi {}

void main() {
  late AppDatabase db;
  late MockExpensesApi expensesApi;
  late ExpenseRepositoryImpl expenseRepository;
  late ExpenseSyncHandler handler;

  // Required — Architecture Section 7a, see expense.dart's own doc
  // comment. A real Locations row must exist before any Expense can be
  // inserted at all (FK enforced in tests too).
  const locationId = 'loc-1';

  setUpAll(() {
    registerFallbackValue(
      ExpenseCreateDto(
        description: 'fallback',
        amount: 0,
        expenseDate: DateTime(2020),
      ),
    );
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesApi = MockExpensesApi();
    expenseRepository = ExpenseRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = ExpenseSyncHandler(
      expensesApi: expensesApi,
      expenseRepository: expenseRepository,
    );

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

  SyncQueueItem queueItemFor(Expense expense, {String operation = 'create'}) {
    return SyncQueueItem(
      id: 'q1',
      entityType: 'expense',
      entityLocalId: expense.localId,
      operation: operation,
      priority: 1,
      enqueuedAt: DateTime.now(),
      syncAttempts: 0,
    );
  }

  test(
      'sends the client_reference equal to the local id, sends the '
      'locationLocalId separately from the DTO, and marks the local '
      'expense synced from the response', () async {
    final expense = await expenseRepository.recordExpense(
      ExpenseDraft(locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
    );

    when(() => expensesApi.createExpense(
          any(),
          locationLocalId: any(named: 'locationLocalId'),
        )).thenAnswer(
      (_) async => Expense(
        localId: expense.localId,
        serverId: 'server-expense-1',
        locationId: expense.locationId,
        description: expense.description,
        amount: expense.amount,
        expenseDate: expense.expenseDate,
        createdAt: expense.createdAt,
        updatedAt: expense.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(expense));

    final captured = verify(() => expensesApi.createExpense(
          captureAny(),
          locationLocalId: captureAny(named: 'locationLocalId'),
        )).captured;
    final dto = captured[0] as ExpenseCreateDto;
    expect(dto.clientReference, expense.localId);
    expect(dto.description, 'Fuel');
    expect(captured[1], locationId);

    final updated = await expenseRepository.getExpenseById(expense.localId);
    expect(updated!.serverId, 'server-expense-1');
  });

  test('throws for an operation other than create', () async {
    final expense = await expenseRepository.recordExpense(
      ExpenseDraft(locationId: locationId, description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
    );

    await expectLater(
      handler.sync(queueItemFor(expense, operation: 'update')),
      throwsA(isA<StateError>()),
    );
  });

  test('throws when the queue item has outlived its own local row', () async {
    final phantomItem = SyncQueueItem(
      id: 'q1',
      entityType: 'expense',
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
