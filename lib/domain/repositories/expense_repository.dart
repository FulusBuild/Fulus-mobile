import '../entities/expense.dart';

/// Architecture Section 4's repository pattern, applied to Expenses.
abstract class ExpenseRepository {
  Future<Expense> recordExpense(ExpenseDraft draft);

  Stream<List<Expense>> watchExpenses(String locationId);

  Future<Expense?> getExpenseById(String localId);

  Future<List<Expense>> getExpensesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  });

  Future<void> markSynced({required String localId, required String serverId});

  Future<Expense> updateExpense({
    required String localId,
    required String description,
    required double amount,
    String? categoryId,
    required DateTime expenseDate,
    String? paymentMethod,
    String? userId,
  });

  Future<void> updateReceiptPhoto({required String localId, required String? photoPath});

  /// Applies server-authoritative expense state without creating an outbound
  /// sync task. The [locationServerId] is resolved to this device's local
  /// location row before the expense is persisted.
  Future<void> reconcileServerState({
    required String serverId,
    required String locationServerId,
    String? categoryId,
    required String description,
    required double amount,
    required DateTime expenseDate,
    String? paymentMethod,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies a server-authoritative deletion without creating an outbound
  /// sync task.
  Future<void> reconcileDeleted(String serverId);
}
