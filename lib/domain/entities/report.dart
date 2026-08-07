/// Reports — Stage 12 (the "Reports" half of "Dashboard / Reports").
///
/// Volume 10 of the Product Design Bible: one reports experience with a
/// shared period selector sitting above five categories (Sales,
/// Inventory, Customers, Finance, Employees) — not eleven separate
/// screens. See report_engine.dart for the period-range math and the
/// rule-based insight generation (Decision 35: retrospective only, never
/// forecasted).

enum ReportPeriodKind { today, thisWeek, thisMonth, custom }

/// A resolved [start, end] date range (inclusive) for whichever period
/// the owner has selected — [ReportsEngine.resolvePeriod] is what turns
/// a [ReportPeriodKind] into one of these; nothing in the UI or the
/// repository layer computes date arithmetic itself.
class ReportPeriod {
  const ReportPeriod({required this.kind, required this.start, required this.end});

  final ReportPeriodKind kind;
  final DateTime start;
  final DateTime end;

  /// The immediately-preceding period of the same length — what
  /// Finance's trend comparison (Volume 10: "extended with a trend
  /// against the previous period of the same length") is computed
  /// against.
  ReportPeriod get previous {
    final length = end.difference(start);
    final prevEnd = start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(length);
    return ReportPeriod(kind: ReportPeriodKind.custom, start: prevStart, end: prevEnd);
  }
}

/// A single rule-based, plain-language observation — Decision 35.
/// Regenerated fresh every time the screen opens (never persisted),
/// which is what the engine's pure-function design gives for free.
class ReportInsight {
  const ReportInsight(this.text);
  final String text;
}

// ── Sales ───────────────────────────────────────────────────────────────────

class SalesByPaymentMethod {
  const SalesByPaymentMethod({required this.method, required this.total, required this.count});
  final String method;
  final double total;
  final int count;
}

class SalesByHour {
  const SalesByHour({required this.hour, required this.total, required this.count});

  /// 0-23, local time.
  final int hour;
  final double total;
  final int count;
}

class TopProduct {
  const TopProduct({required this.productName, required this.quantitySold, required this.revenue});
  final String productName;
  final int quantitySold;
  final double revenue;
}

class SalesReport {
  const SalesReport({
    required this.period,
    required this.totalRevenue,
    required this.totalSalesCount,
    required this.totalDiscount,
    required this.totalTax,
    required this.byPaymentMethod,
    required this.byHour,
    required this.topProducts,
    required this.insights,
  });

  final ReportPeriod period;
  final double totalRevenue;
  final int totalSalesCount;
  final double totalDiscount;
  final double totalTax;
  final List<SalesByPaymentMethod> byPaymentMethod;
  final List<SalesByHour> byHour;
  final List<TopProduct> topProducts;
  final List<ReportInsight> insights;
}

// ── Inventory ───────────────────────────────────────────────────────────────

class InventoryReport {
  const InventoryReport({
    required this.totalStockValue,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.totalProducts,
    required this.stockMovementsIn,
    required this.stockMovementsOut,
    required this.notSoldInThirtyDays,
    required this.insights,
  });

  final double totalStockValue;
  final int lowStockCount;
  final int outOfStockCount;
  final int totalProducts;
  final int stockMovementsIn;
  final int stockMovementsOut;

  /// Product names — Volume 10's "anything that hasn't sold in 30 days".
  final List<String> notSoldInThirtyDays;
  final List<ReportInsight> insights;
}

// ── Customers ───────────────────────────────────────────────────────────────

class TopCustomer {
  const TopCustomer({required this.customerName, required this.totalSpend});
  final String customerName;
  final double totalSpend;
}

class CustomerReport {
  const CustomerReport({
    required this.period,
    required this.topCustomers,
    required this.totalOutstandingCredit,
    required this.newCustomersThisPeriod,
    required this.insights,
  });

  final ReportPeriod period;
  final List<TopCustomer> topCustomers;
  final double totalOutstandingCredit;
  final int newCustomersThisPeriod;
  final List<ReportInsight> insights;
}

// ── Finance ─────────────────────────────────────────────────────────────────

class FinanceReport {
  const FinanceReport({
    required this.period,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netProfit,
    required this.previousPeriodNetProfit,
    required this.expenseBreakdown,
    required this.insights,
  });

  final ReportPeriod period;
  final double totalRevenue;
  final double totalExpenses;
  final double netProfit;

  /// Same-length prior period's net profit — the trend comparison
  /// Volume 10 calls for; null when there's no prior data at all (e.g.
  /// a business in its first period), in which case the engine omits
  /// the trend line entirely rather than showing a misleading "+100%".
  final double? previousPeriodNetProfit;
  final List<ExpenseCategoryTotal> expenseBreakdown;
  final List<ReportInsight> insights;

  double? get profitTrendPercent {
    final prev = previousPeriodNetProfit;
    if (prev == null || prev == 0) return null;
    return ((netProfit - prev) / prev.abs()) * 100;
  }
}

class ExpenseCategoryTotal {
  const ExpenseCategoryTotal({required this.category, required this.total});
  final String category;
  final double total;
}

// ── Employees ───────────────────────────────────────────────────────────────

/// Deliberately NOT sortable/rankable by the UI — Volume 10 is explicit
/// ("presented factually, never as a ranked comparison between named
/// individuals"). This type carries no rank field on purpose; a screen
/// that wants a leaderboard would have to add one against the spec, not
/// just read one off this model.
class EmployeePerformance {
  const EmployeePerformance({
    required this.employeeId,
    required this.employeeName,
    required this.salesTotal,
    required this.salesCount,
    required this.daysPresent,
    required this.daysAbsent,
    required this.daysLate,
  });

  final String employeeId;
  final String employeeName;
  final double salesTotal;
  final int salesCount;
  final int daysPresent;
  final int daysAbsent;
  final int daysLate;
}

class EmployeeReport {
  const EmployeeReport({
    required this.period,
    required this.performance,
    required this.insights,
  });

  final ReportPeriod period;
  final List<EmployeePerformance> performance;
  final List<ReportInsight> insights;
}
