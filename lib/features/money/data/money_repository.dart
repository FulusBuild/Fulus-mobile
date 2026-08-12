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

  Future<MoneySummary> getSummary(ReportPeriod period);

  /// Reverse-chronological, matching every other history view in this
  /// codebase's own convention.
  Future<List<MoneyTransaction>> getTransactions(
    ReportPeriod period, {
    MoneyTransactionType? typeFilter,

    /// Only meaningful alongside `typeFilter: MoneyTransactionType.expense`
    /// — narrows to one expense category (e.g. "Rent"), matching a
    /// tapped `MoneyBreakdownSection` row exactly rather than every
    /// expense in the period.
    String? category,
    String? searchQuery,
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
  });

  // ── Cash Drawer & Daily Closing ─────────────────────────────────────

  Future<MoneyDrawerSession?> getActiveDrawerSession();

  Future<MoneyDrawerSession> openDrawer({required double openingFloat});

  Future<MoneyExpectedCashPreview> computeExpectedCash();

  /// Closes the active session and returns the day's summary. Throws
  /// [StateError] if no drawer is currently open.
  Future<DailyClosingSummary> closeDrawer({required double countedCash, String? note});
}
