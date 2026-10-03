import '../../../core/money/money.dart';

/// Volume 8's Cash Drawer & Opening Float + Daily Closing, mirroring
/// the real (but locationId-gated — see money_transaction.dart's own
/// doc comment) `CashDrawerShift`/`CashDrawerShiftRepository` shape,
/// backed by this feature's mock data for the same reason.
class MoneyDrawerSession {
  const MoneyDrawerSession({required this.openingFloat, required this.openedAt});

  final Money openingFloat;
  final DateTime openedAt;
}

/// [MoneyRepository.computeExpectedCash]'s result — "opening float,
/// plus cash sales, minus cash-method expenses" (Volume 8), previewed
/// before the day is actually closed.
class MoneyExpectedCashPreview {
  const MoneyExpectedCashPreview({
    required this.openingFloat,
    required this.cashSales,
    required this.cashExpenses,
  });

  final Money openingFloat;
  final Money cashSales;
  final Money cashExpenses;
  Money get expectedCash => openingFloat + cashSales - cashExpenses;
}

/// The Daily Closing Summary screen's data — "counted, expected,
/// difference — never an interrogation" (Volume 8), plus the
/// by-payment-method sales split ("Paid with" isn't a formality").
class DailyClosingSummary {
  const DailyClosingSummary({
    required this.closedAt,
    required this.salesByMethod,
    required this.expensesTotal,
    required this.netForDay,
    required this.expectedCash,
    required this.countedCash,
    required this.note,
  });

  final DateTime closedAt;

  /// Method label -> total sold, e.g. {"Cash": 42000, "Mobile Money": 18500}.
  final Map<String, Money> salesByMethod;
  final Money expensesTotal;
  final Money netForDay;
  final Money expectedCash;
  final Money countedCash;
  final String? note;

  Money get difference => countedCash - expectedCash;
  Money get totalSales => salesByMethod.values.fold(0, (a, b) => a + b);
}
