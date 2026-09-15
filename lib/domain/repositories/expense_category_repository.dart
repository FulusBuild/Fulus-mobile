import '../entities/expense_category.dart';

abstract class ExpenseCategoryRepository {
  Future<ExpenseCategory> createExpenseCategory(ExpenseCategoryDraft draft);

  Stream<List<ExpenseCategory>> watchExpenseCategories();

  Future<ExpenseCategory?> getExpenseCategoryById(String localId);

  Future<void> markSynced({required String localId, required String serverId});

  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  Future<void> reconcileDeleted(String serverId);
}
