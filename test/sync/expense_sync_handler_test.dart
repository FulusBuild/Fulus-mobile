import 'package:bms_mobile/data/local/database/database.dart';
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

  setUpAll(() {
    registerFallbackValue(
      ExpenseCreateDto(
        description: 'fallback',
        amount: 0,
        expenseDate: DateTime(2020),
      ),
    );
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesApi = MockExpensesApi();
    expenseRepository = ExpenseRepositoryImpl(db: db, syncQueue: SyncQueue(db));
    handler = ExpenseSyncHandler(
      expensesApi: expensesApi,
      expenseRepository: expenseRepository,
    );
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
      'sends the client_reference equal to the local id and marks the '
      'local expense synced from the response', () async {
    final expense = await expenseRepository.recordExpense(
      ExpenseDraft(description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
    );

    when(() => expensesApi.createExpense(any())).thenAnswer(
      (_) async => Expense(
        localId: expense.localId,
        serverId: 'server-expense-1',
        description: expense.description,
        amount: expense.amount,
        expenseDate: expense.expenseDate,
        createdAt: expense.createdAt,
        updatedAt: expense.updatedAt,
      ),
    );

    await handler.sync(queueItemFor(expense));

    final captured = verify(() => expensesApi.createExpense(captureAny())).captured;
    final dto = captured.single as ExpenseCreateDto;
    expect(dto.clientReference, expense.localId);
    expect(dto.description, 'Fuel');

    final updated = await expenseRepository.getExpenseById(expense.localId);
    expect(updated!.serverId, 'server-expense-1');
  });

  test('throws for an operation other than create', () async {
    final expense = await expenseRepository.recordExpense(
      ExpenseDraft(description: 'Fuel', amount: 3000, expenseDate: DateTime(2026, 7, 1)),
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
