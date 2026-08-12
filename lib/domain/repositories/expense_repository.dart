import '../entities/expense.dart';

/// Architecture Section 4's repository pattern, applied to Expenses.
/// Follows SaleRepository's exact shape: recording an expense on the go
/// (no signal, no receipt to wait for) is exactly the kind of write
/// that must succeed locally and sync later, not block on connectivity.
abstract class ExpenseRepository {
  Future<Expense> recordExpense(ExpenseDraft draft);

  /// [locationId] required, not optional — CORRECTED (see expense.dart's
  /// own doc comment for the full story of getting this backwards).
  /// Matches SaleRepository.watchSalesForToday's identical treatment
  /// exactly. Previously `watchExpenses({String? locationId})`.
  Stream<List<Expense>> watchExpenses(String locationId);

  Future<Expense?> getExpenseById(String localId);

  /// All expenses for [locationId] with `expenseDate` inside
  /// [start, end] (inclusive of both ends' full calendar days) —
  /// the period-scoped sibling of [watchExpenses], added for Volume 8's
  /// Money/Cash Flow feature. One-shot Future, matching
  /// `features/money/data/money_repository.dart`'s own interface shape.
  Future<List<Expense>> getExpensesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  });

  Future<void> markSynced({required String localId, required String serverId});
}
