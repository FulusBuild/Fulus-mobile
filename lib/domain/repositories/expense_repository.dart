import '../entities/expense.dart';

/// Architecture Section 4's repository pattern, applied to Expenses.
/// Follows SaleRepository's exact shape: recording an expense on the go
/// (no signal, no receipt to wait for) is exactly the kind of write
/// that must succeed locally and sync later, not block on connectivity.
abstract class ExpenseRepository {
  Future<Expense> recordExpense(ExpenseDraft draft);

  /// [locationId] is an optional filter, not a required scope — unlike
  /// Sale, Expense has no server-side location concept at all (see
  /// Expense's own doc comment), so most expenses may have no location
  /// tag whatsoever. Omit it to watch every expense.
  Stream<List<Expense>> watchExpenses({String? locationId});

  Future<Expense?> getExpenseById(String localId);

  Future<void> markSynced({required String localId, required String serverId});
}
