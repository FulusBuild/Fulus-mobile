import '../../../domain/entities/report.dart';
import '../domain/cash_drawer_state.dart';
import '../domain/money_summary.dart';
import '../domain/money_transaction.dart';

/// See `money_transaction.dart`'s doc comment for the full real-vs-mock
/// history. `RealMoneyRepositoryImpl` (`real_money_repository.dart`) is
/// the real implementation `moneyRepositoryProvider` returns now;
/// [MockMoneyRepository] remains as a reference/testing implementation
/// only.
abstract class MoneyRepository {
  /// All-time net (every transaction ever recorded, signed and summed) —
  /// this feature's stand-in for "current balance," since nothing in
  /// the real domain persists a running balance. Not period-scoped —
  /// like a bank app's balance, it doesn't move when the period filter
  /// changes, only when a new transaction is recorded.
  Future<double> getAvailableBalance();

  /// Employee data isolation: [currentAuthUserId] and [canViewAllSales]
  /// scope every sale-derived figure here to one cashier when
  /// [canViewAllSales] is false — see `_transactionsForRange`'s own doc
  /// comment in `real_money_repository.dart` for exactly what is and
  /// isn't included in that scoping (expenses/income/repayments/
  /// supplier-payments have no user attribution to scope by, so they're
  /// dropped rather than shown unscoped). Required, not optional-with-a-
  /// default: a forgotten default here would mean silently showing
  /// everyone's numbers to whoever's logged in, exactly the failure mode
  /// this exists to prevent.
  Future<MoneySummary> getSummary(
    ReportPeriod period, {
    required String currentAuthUserId,
    required bool canViewAllSales,
  });

  /// Reverse-chronological, matching every other history view in this
  /// codebase's own convention. See [getSummary] on the scoping params.
  Future<List<MoneyTransaction>> getTransactions(
    ReportPeriod period, {
    required String currentAuthUserId,
    required bool canViewAllSales,
    MoneyTransactionType? typeFilter,

    /// Only meaningful alongside `typeFilter: MoneyTransactionType.expense`
    /// — narrows to one expense category (e.g. "Rent"), matching a
    /// tapped `MoneyBreakdownSection` row exactly rather than every
    /// expense in the period.
    String? category,
    String? searchQuery,
  });

  /// Every sale ever recorded for [customerId], most recent first — the
  /// customer profile's Purchase History (Volume 7). Deliberately NOT
  /// period-scoped (like [getAvailableBalance], not like [getSummary]/
  /// [getTransactions] above) and NOT limited to whichever location
  /// [getTransactions] resolves via `ResolveActiveLocation` — see
  /// `SaleRepository.getSalesForCustomer`'s own doc comment for why:
  /// a customer's purchase history is business-wide. Employee data
  /// isolation: same [currentAuthUserId]/[canViewAllSales] contract as
  /// [getSummary]/[getTransactions] above.
  Future<List<MoneyTransaction>> getTransactionsForCustomer(
    String customerId, {
    required String currentAuthUserId,
    required bool canViewAllSales,
  });

  Future<MoneyTransaction?> getTransactionById(String id);

  Future<MoneyTransaction> recordIncome({
    required double amount,
    required String source,
    String? note,
  });

  Future<MoneyTransaction> recordExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,

    /// See `Expense.receiptPhotoPath`'s own doc comment — a local file
    /// path from `PhotoCaptureScreen`, captured before this expense was
    /// ever saved. Gap-closure pass: "Receipt photo attachment on
    /// expenses."
    String? receiptPhotoPath,
  });

  /// Attaches, replaces, or removes (pass `null`) the receipt photo on
  /// an already-recorded expense transaction — [transactionId] is a
  /// [MoneyTransaction.id] (the `expense-<localId>`-prefixed form), not
  /// a bare `Expense.localId`. Throws [ArgumentError] if [transactionId]
  /// doesn't refer to an expense — there is no receipt-photo concept
  /// for a sale, income record, repayment, or supplier payment.
  Future<MoneyTransaction> attachReceiptPhoto({
    required String transactionId,
    required String? photoPath,
  });

  // ── Cash Drawer & Daily Closing ─────────────────────────────────────

  Future<MoneyDrawerSession?> getActiveDrawerSession();

  Future<MoneyDrawerSession> openDrawer({required double openingFloat});

  Future<MoneyExpectedCashPreview> computeExpectedCash();

  /// Closes the active session and returns the day's summary. Throws
  /// [StateError] if no drawer is currently open.
  Future<DailyClosingSummary> closeDrawer({required double countedCash, String? note});
}
