/// Mirrors the Expenses table exactly — locationId is required, per
/// Architecture Section 7a's confirmed answer (same as Sales, not
/// nullable, even for a single-location business).
class Expense {
  const Expense({
    required this.localId,
    this.serverId,
    required this.locationId,
    this.categoryId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String locationId;
  final String? categoryId;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethod;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// The not-yet-persisted input to ExpenseRepository.recordExpense.
class ExpenseDraft {
  const ExpenseDraft({
    required this.locationId,
    this.categoryId,
    required this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod,
  });

  final String locationId;
  final String? categoryId;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? paymentMethod;

  Expense toExpenseEntity({required String localId}) {
    final now = DateTime.now();
    return Expense(
      localId: localId,
      locationId: locationId,
      categoryId: categoryId,
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      paymentMethod: paymentMethod,
      createdAt: now,
      updatedAt: now,
    );
  }
}
