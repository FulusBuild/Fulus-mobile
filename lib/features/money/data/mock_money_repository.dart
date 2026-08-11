import '../../../domain/entities/report.dart';
import '../domain/cash_drawer_state.dart';
import '../domain/money_summary.dart';
import '../domain/money_transaction.dart';
import 'mock_money_data.dart';
import 'money_repository.dart';

/// See `money_repository.dart` / `money_transaction.dart` for why this
/// is the only [MoneyRepository] implementation today. A short,
/// simulated latency on every read is deliberate — it's what lets the
/// Cash Flow screen's skeleton/loading states actually be exercised by
/// a reviewer rather than only existing in code that never visibly
/// runs, the same reasoning `FulusDelayedSkeleton` itself is built
/// around.
class MockMoneyRepository implements MoneyRepository {
  MockMoneyRepository() : _transactions = generateMockMoneyTransactions();

  final List<MoneyTransaction> _transactions;
  MoneyDrawerSession? _drawerSession;

  /// Debug-only switch (see `money_screen.dart`'s bug-report icon,
  /// `kDebugMode`-gated) so this screen's [FulusErrorState] paths are
  /// something a reviewer can actually trigger, rather than dead code
  /// that only ever exists on paper. Left `false` by default and never
  /// flipped by anything except that explicit debug action.
  bool debugSimulateFailure = false;

  /// 600ms — deliberately past [FulusDelayedSkeleton]'s 400ms threshold,
  /// so a skeleton wrapped in that widget is actually reachable by a
  /// reviewer rather than resolving too fast to ever render.
  static const _simulatedLatency = Duration(milliseconds: 600);

  Future<void> _delay() async {
    await Future.delayed(_simulatedLatency);
    if (debugSimulateFailure) {
      throw Exception('Simulated failure (debug) — this only happens because the debug bug-report icon was tapped.');
    }
  }

  /// [period.end] is date-only (see `ReportsEngine.resolvePeriod`) — the
  /// upper bound here is exclusive of the *next* day, so a period's own
  /// end date is fully included through 23:59:59.
  bool _inPeriod(MoneyTransaction t, ReportPeriod period) {
    final upperBoundExclusive = period.end.add(const Duration(days: 1));
    return !t.dateTime.isBefore(period.start) && t.dateTime.isBefore(upperBoundExclusive);
  }

  @override
  Future<double> getAvailableBalance() async {
    await _delay();
    return _transactions.fold<double>(0, (sum, t) => sum + t.signedAmount);
  }

  @override
  Future<MoneySummary> getSummary(ReportPeriod period) async {
    await _delay();
    final inPeriod = _transactions.where((t) => _inPeriod(t, period)).toList();

    double sumWhere(bool Function(MoneyTransaction) test) =>
        inPeriod.where(test).fold<double>(0, (sum, t) => sum + t.amount);

    final moneyIn = sumWhere((t) => t.isInflow);
    final moneyOut = sumWhere((t) => !t.isInflow);

    final previousPeriod = period.previous;
    final previousNet = _transactions
        .where((t) => _inPeriod(t, previousPeriod))
        .fold<double>(0, (sum, t) => sum + t.signedAmount);

    return MoneySummary(
      period: period,
      moneyIn: moneyIn,
      moneyOut: moneyOut,
      previousNet: previousNet,
      incomeBreakdown: _breakdownIncome(inPeriod),
      expenseBreakdown: _breakdownExpense(inPeriod),
      transactionCount: inPeriod.length,
    );
  }

  List<CategoryTotal> _breakdownIncome(List<MoneyTransaction> inPeriod) {
    final rows = <CategoryTotal>[];
    void addBucket(String label, MoneyTransactionType type) {
      final matches = inPeriod.where((t) => t.type == type).toList();
      if (matches.isEmpty) return;
      rows.add(CategoryTotal(
        label: label,
        amount: matches.fold<double>(0, (sum, t) => sum + t.amount),
        count: matches.length,
        type: type,
      ));
    }

    addBucket('Sales income', MoneyTransactionType.saleIncome);
    addBucket('Customer repayments', MoneyTransactionType.customerRepayment);
    addBucket('Other income', MoneyTransactionType.manualIncome);
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  List<CategoryTotal> _breakdownExpense(List<MoneyTransaction> inPeriod) {
    final byCategory = <String, List<MoneyTransaction>>{};
    for (final t in inPeriod.where((t) => t.type == MoneyTransactionType.expense)) {
      byCategory.putIfAbsent(t.category ?? 'Other', () => []).add(t);
    }
    final rows = [
      for (final entry in byCategory.entries)
        CategoryTotal(
          label: entry.key,
          amount: entry.value.fold<double>(0, (sum, t) => sum + t.amount),
          count: entry.value.length,
          type: MoneyTransactionType.expense,
        ),
    ];
    final supplierPayments = inPeriod.where((t) => t.type == MoneyTransactionType.supplierPayment).toList();
    if (supplierPayments.isNotEmpty) {
      rows.add(CategoryTotal(
        label: 'Supplier payments',
        amount: supplierPayments.fold<double>(0, (sum, t) => sum + t.amount),
        count: supplierPayments.length,
        type: MoneyTransactionType.supplierPayment,
      ));
    }
    rows.sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }

  @override
  Future<List<MoneyTransaction>> getTransactions(
    ReportPeriod period, {
    MoneyTransactionType? typeFilter,
    String? category,
    String? searchQuery,
  }) async {
    await _delay();
    final query = searchQuery?.trim().toLowerCase();
    return _transactions.where((t) {
      if (!_inPeriod(t, period)) return false;
      if (typeFilter != null && t.type != typeFilter) return false;
      if (category != null && t.category != category) return false;
      if (query != null && query.isNotEmpty) {
        final haystack = [t.title, t.subtitle, t.counterpartyName, t.reference]
            .where((s) => s != null)
            .map((s) => s!.toLowerCase())
            .join(' ');
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<MoneyTransaction?> getTransactionById(String id) async {
    await _delay();
    for (final t in _transactions) {
      if (t.id == id) return t;
    }
    return null;
  }

  int _sequence = 100000;
  String _nextId() => 'txn-manual-${(_sequence++)}';

  @override
  Future<MoneyTransaction> recordIncome({
    required double amount,
    required String source,
    String? note,
  }) async {
    await _delay();
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }
    final transaction = MoneyTransaction(
      id: _nextId(),
      type: MoneyTransactionType.manualIncome,
      title: source,
      subtitle: 'Other income',
      amount: amount,
      dateTime: DateTime.now(),
      note: note,
    );
    _transactions.insert(0, transaction);
    return transaction;
  }

  @override
  Future<MoneyTransaction> recordExpense({
    required double amount,
    required String category,
    required String paymentMethod,
    String? note,
  }) async {
    await _delay();
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be > 0');
    }
    final transaction = MoneyTransaction(
      id: _nextId(),
      type: MoneyTransactionType.expense,
      title: category,
      subtitle: category,
      category: category,
      amount: amount,
      dateTime: DateTime.now(),
      paymentMethod: paymentMethod,
      note: note,
    );
    _transactions.insert(0, transaction);
    return transaction;
  }

  // ── Cash Drawer & Daily Closing ───────────────────────────────────────

  @override
  Future<MoneyDrawerSession?> getActiveDrawerSession() async {
    await _delay();
    return _drawerSession;
  }

  @override
  Future<MoneyDrawerSession> openDrawer({required double openingFloat}) async {
    await _delay();
    final session = MoneyDrawerSession(openingFloat: openingFloat, openedAt: DateTime.now());
    _drawerSession = session;
    return session;
  }

  @override
  Future<MoneyExpectedCashPreview> computeExpectedCash() async {
    await _delay();
    final session = _drawerSession;
    if (session == null) {
      throw StateError('No drawer is currently open.');
    }
    return _expectedCashFor(session);
  }

  MoneyExpectedCashPreview _expectedCashFor(MoneyDrawerSession session) {
    final sinceOpen = _transactions.where((t) => t.dateTime.isAfter(session.openedAt));
    final cashSales = sinceOpen
        .where((t) => t.type == MoneyTransactionType.saleIncome && t.paymentMethod == 'Cash')
        .fold<double>(0, (sum, t) => sum + t.amount);
    final cashOut = sinceOpen
        .where((t) =>
            (t.type == MoneyTransactionType.expense || t.type == MoneyTransactionType.supplierPayment) &&
            t.paymentMethod == 'Cash')
        .fold<double>(0, (sum, t) => sum + t.amount);
    return MoneyExpectedCashPreview(
      openingFloat: session.openingFloat,
      cashSales: cashSales,
      cashExpenses: cashOut,
    );
  }

  @override
  Future<DailyClosingSummary> closeDrawer({required double countedCash, String? note}) async {
    await _delay();
    final session = _drawerSession;
    if (session == null) {
      throw StateError('No drawer is currently open.');
    }
    final preview = _expectedCashFor(session);
    final sinceOpen = _transactions.where((t) => t.dateTime.isAfter(session.openedAt)).toList();

    final salesByMethod = <String, double>{};
    for (final t in sinceOpen.where((t) => t.type == MoneyTransactionType.saleIncome)) {
      final method = t.paymentMethod ?? 'Other';
      salesByMethod.update(method, (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    final expensesTotal = sinceOpen
        .where((t) => t.type == MoneyTransactionType.expense || t.type == MoneyTransactionType.supplierPayment)
        .fold<double>(0, (sum, t) => sum + t.amount);
    final totalSales = salesByMethod.values.fold<double>(0, (a, b) => a + b);

    final summary = DailyClosingSummary(
      closedAt: DateTime.now(),
      salesByMethod: salesByMethod,
      expensesTotal: expensesTotal,
      netForDay: totalSales - expensesTotal,
      expectedCash: preview.expectedCash,
      countedCash: countedCash,
      note: note,
    );
    _drawerSession = null;
    return summary;
  }
}
