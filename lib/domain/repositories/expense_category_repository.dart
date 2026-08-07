import '../entities/expense_category.dart';

abstract class ExpenseCategoryRepository {
  Future<ExpenseCategory> createExpenseCategory(ExpenseCategoryDraft draft);

  Stream<List<ExpenseCategory>> watchExpenseCategories();

  Future<ExpenseCategory?> getExpenseCategoryById(String localId);

  Future<void> markSynced({required String localId, required String serverId});
}
