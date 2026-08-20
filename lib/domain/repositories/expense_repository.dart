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

  /// Edits an already-saved expense in place, keeping a real history of
  /// the change rather than silently overwriting it — via
  /// AuditRepository (module `expenses`, action `expense.updated`,
  /// `details` carrying the before/after values), the same
  /// infrastructure Auth/PIN-approval/customer-credit already use, not
  /// a new mechanism. [userId] is the editor, for that trail — same
  /// "caller supplies who, not this method" split every other
  /// permission-adjacent write in this codebase follows.
  ///
  /// Local-only for now: there's no confirmed backend endpoint for
  /// updating an expense (only `createExpense` has a sync task — see
  /// sync_queue.dart), so this does not enqueue one. Revisit once
  /// that's confirmed one way or the other; inventing a sync task
  /// against an unconfirmed backend contract would be a worse guess
  /// than not syncing the edit at all.
  Future<Expense> updateExpense({
    required String localId,
    required String description,
    required double amount,
    String? categoryId,
    required DateTime expenseDate,
    String? paymentMethod,
    String? userId,
  });

  /// Attaches, replaces, or removes (pass `null`) the receipt photo on
  /// an already-saved expense — the after-the-fact counterpart to
  /// [ExpenseDraft.receiptPhotoPath] (attaching one at creation time,
  /// on Add Expense itself). Gap-closure pass: "Receipt photo
  /// attachment on expenses." Does not enqueue a sync task — see
  /// [Expense.receiptPhotoPath]'s own doc comment for why this field
  /// never syncs at all.
  Future<void> updateReceiptPhoto({required String localId, required String? photoPath});
}
