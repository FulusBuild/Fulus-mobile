import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/expenses_api.dart';
import '../../domain/repositories/expense_repository.dart';
import '../sync_handler.dart';

class ExpenseSyncHandler implements SyncHandler {
  ExpenseSyncHandler({
    required ExpensesApi expensesApi,
    required ExpenseRepository expenseRepository,
  })  : _expensesApi = expensesApi,
        _expenseRepository = expenseRepository;

  final ExpensesApi _expensesApi;
  final ExpenseRepository _expenseRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'ExpenseSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final expense = await _expenseRepository.getExpenseById(item.entityLocalId);
    if (expense == null) {
      throw StateError(
        'No local expense found for ${item.entityLocalId} — the queue '
        'item outlived its own row.',
      );
    }

    final response = await _expensesApi.createExpense(
      expense.toCreateDto(clientReference: expense.localId),
      locationLocalId: expense.locationId,
    );

    await _expenseRepository.markSynced(
      localId: expense.localId,
      serverId: response.serverId!,
    );
  }
}
