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
  const TopProduct({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
  });

  /// **New** (gap-closure pass: "Reports drill-down") — a
  /// `Product.localId`, so a tapped row can open that product's own
  /// detail screen instead of the report only ever being a dead end.
  final String productId;
  final String productName;
  final int quantitySold;
  final double revenue;
}

/// completed: no return against this sale has ever been completed.
/// partiallyRefunded/refunded: a completed, non-void return exists,
/// covering less than / all of what was purchased. voided: a completed
/// return tagged isVoid exists — see ReturnRequests.isVoid's own doc
/// comment in tables.dart for what distinguishes the two.
enum SaleRecordStatus { completed, partiallyRefunded, refunded, voided }

/// One row of the Sales report's drill-down — the audit trail your
/// brief asked for: "revenue → sales transactions → individual sale →
/// ... → payment → customer → cashier/user → timestamp →
/// receipt/reference." Every field here is read straight off the real
/// Sale record (see ReportsRepositoryImpl.getSalesReport) — nothing
/// computed or estimated.
class SaleRecord {
  const SaleRecord({
    required this.saleLocalId,
    required this.saleDate,
    this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.cashierUserId,
    this.cashierName,
    this.paymentMethod,
    required this.total,
    required this.discount,
    required this.status,
  });

  final String saleLocalId;
  final DateTime saleDate;

  /// Falls back to a truncated `saleLocalId` when null, same convention
  /// receipts and global search already use — see
  /// ReportsRepositoryImpl.getSalesReport for exactly where.
  final String? invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? cashierUserId;

  /// Null when [cashierUserId] itself is null (a sale recorded before
  /// schema v4 added the column) or, less commonly, when that user has
  /// since been removed — the report doesn't hide the sale in either
  /// case, it just can't say who rang it up.
  final String? cashierName;
  final String? paymentMethod;
  final double total;
  final double discount;
  final SaleRecordStatus status;
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
    required this.transactions,
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

  /// The drill-down list — every sale in [period], newest first. Not
  /// paginated at the domain layer; ReportsRepositoryImpl's own doc
  /// comment covers the same "acceptable at today's scale, revisit if
  /// that assumption stops holding" reasoning this app already applies
  /// elsewhere (e.g. InventoryReport.notSoldInThirtyDays).
  final List<SaleRecord> transactions;
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

  /// **Cost value, not selling value** — `sum(currentStock *
  /// product.costPrice)` (see `ReportsRepositoryImpl.
  /// getInventoryReport`). Verified directly against the repository;
  /// the UI label now says "at cost" explicitly rather than leaving
  /// which basis this uses ambiguous (inventory audit).
  final double totalStockValue;
  final int lowStockCount;
  final int outOfStockCount;
  final int totalProducts;

  /// Total quantity moved in/out via manual Stock In/Stock Out in the
  /// last 30 days — the same rolling window [notSoldInThirtyDays]
  /// already uses, since this report takes no period of its own.
  /// Excludes 'adjustment' and 'sale'-type movements: an adjustment is
  /// a correction, not a genuine in/out event, and a sale-triggered
  /// movement is already fully represented by the Sales report.
  final int stockMovementsIn;
  final int stockMovementsOut;

  /// Product names — Volume 10's "anything that hasn't sold in 30 days".
  final List<String> notSoldInThirtyDays;
  final List<ReportInsight> insights;
}

// ── Customers ───────────────────────────────────────────────────────────────

class TopCustomer {
  const TopCustomer({required this.customerId, required this.customerName, required this.totalSpend});

  /// **New** (gap-closure pass: "Reports drill-down") — a
  /// `Customer.localId`, so a tapped row can open that customer's own
  /// profile instead of the report only ever being a dead end.
  final String customerId;
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
    required this.totalCostOfGoodsSold,
    required this.totalExpenses,
    required this.netProfit,
    required this.previousPeriodNetProfit,
    required this.expenseBreakdown,
    required this.insights,
  });

  final ReportPeriod period;
  final double totalRevenue;

  /// Added alongside the bug fix that made `netProfit` COGS-aware
  /// (previously `revenue - expenses`, now `revenue -
  /// totalCostOfGoodsSold - expenses` — see `ReportsRepositoryImpl.
  /// getFinanceReport`'s own comment for the full history). Exposed
  /// here, not folded silently into `netProfit`, so a future Finance
  /// tab can show the breakdown rather than just a smaller number with
  /// no explanation for why it changed.
  final double totalCostOfGoodsSold;
  final double totalExpenses;
  final double netProfit;

  /// Same-length prior period's net profit — the trend comparison
  /// Volume 10 calls for; null when there's no prior data at all (e.g.
  /// a business in its first period), in which case the engine omits
  /// the trend line entirely rather than showing a misleading "+100%".
  final double? previousPeriodNetProfit;
  final List<ExpenseCategoryTotal> expenseBreakdown;
  final List<ReportInsight> insights;

  /// Revenue after cost of goods sold but before operating expenses —
  /// the intermediate figure between `totalRevenue` and `netProfit`.
  double get grossProfit => totalRevenue - totalCostOfGoodsSold;

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
