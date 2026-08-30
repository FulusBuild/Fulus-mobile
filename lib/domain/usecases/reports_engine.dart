import '../entities/report.dart';

/// Stage 12's pure-logic layer for Reports. ReportsRepositoryImpl does
/// the actual aggregation (querying and summing rows via Drift — which
/// inherently has to know the real Stage 5-8 column names, so that
/// stays confined to the repository as the documented integration
/// seam). This engine only resolves date ranges and turns already-
/// aggregated numbers into Decision 35's rule-based, plain-language,
/// STRICTLY RETROSPECTIVE insights — e.g. "your busiest hour was 2-3pm"
/// is a fact about the period just observed; nothing here ever
/// projects, predicts, or recommends.
class ReportsEngine {
  const ReportsEngine();

  /// Turns a [ReportPeriodKind] into concrete [start, end] dates.
  /// [now] is injectable for tests; [customStart]/[customEnd] are
  /// required only when [kind] is [ReportPeriodKind.custom].
  ReportPeriod resolvePeriod(
    ReportPeriodKind kind, {
    DateTime? now,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    switch (kind) {
      case ReportPeriodKind.today:
        return ReportPeriod(kind: kind, start: today, end: today);
      case ReportPeriodKind.thisWeek:
        // Monday-start week, matching the ISO week convention already
        // used elsewhere in this codebase's date handling.
        final start = today.subtract(Duration(days: today.weekday - 1));
        return ReportPeriod(kind: kind, start: start, end: today);
      case ReportPeriodKind.thisMonth:
        final start = DateTime(today.year, today.month, 1);
        return ReportPeriod(kind: kind, start: start, end: today);
      case ReportPeriodKind.custom:
        if (customStart == null || customEnd == null) {
          throw ArgumentError('customStart and customEnd are required for ReportPeriodKind.custom');
        }
        return ReportPeriod(kind: kind, start: _dateOnly(customStart), end: _dateOnly(customEnd));
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ── Insight generation (Decision 35: retrospective only) ─────────────────

  List<ReportInsight> salesInsights({
    required List<SalesByPaymentMethod> byPaymentMethod,
    required List<SalesByHour> byHour,
    required List<TopProduct> topProducts,
  }) {
    final insights = <ReportInsight>[];

    if (byPaymentMethod.isNotEmpty) {
      final top = [...byPaymentMethod]..sort((a, b) => b.total.compareTo(a.total));
      insights.add(ReportInsight('Most sales were paid by ${top.first.method}.'));
    }
    if (byHour.isNotEmpty) {
      final busiest = [...byHour]..sort((a, b) => b.total.compareTo(a.total));
      final h = busiest.first.hour;
      insights.add(ReportInsight('Your busiest hour was ${_formatHourRange(h)}.'));
    }
    if (topProducts.isNotEmpty) {
      insights.add(ReportInsight('${topProducts.first.productName} was your top-selling product.'));
    }
    return insights;
  }

  List<ReportInsight> inventoryInsights({
    required int lowStockCount,
    required int outOfStockCount,
    required int notSoldInThirtyDaysCount,
  }) {
    final insights = <ReportInsight>[];
    if (outOfStockCount > 0) {
      insights.add(ReportInsight('$outOfStockCount product${outOfStockCount == 1 ? '' : 's'} out of stock.'));
    }
    if (lowStockCount > 0) {
      insights.add(ReportInsight('$lowStockCount product${lowStockCount == 1 ? '' : 's'} running low.'));
    }
    if (notSoldInThirtyDaysCount > 0) {
      insights.add(ReportInsight(
          '$notSoldInThirtyDaysCount product${notSoldInThirtyDaysCount == 1 ? '' : 's'} haven\'t sold in the last 30 days.'));
    }
    return insights;
  }

  List<ReportInsight> customerInsights({
    required int newCustomersThisPeriod,
    required double totalOutstandingCredit,
    required List<TopCustomer> topCustomers,
  }) {
    final insights = <ReportInsight>[];
    if (newCustomersThisPeriod > 0) {
      insights.add(ReportInsight('$newCustomersThisPeriod new customer${newCustomersThisPeriod == 1 ? '' : 's'} this period.'));
    }
    if (topCustomers.isNotEmpty) {
      insights.add(ReportInsight('${topCustomers.first.customerName} was your top customer by spend.'));
    }
    if (totalOutstandingCredit > 0) {
      insights.add(const ReportInsight('There is outstanding customer credit to collect.'));
    }
    return insights;
  }

  /// [previousNetProfit] null means no comparable prior period — the
  /// trend line is omitted entirely rather than fabricating a "+100%"
  /// against a zero or missing baseline (see FinanceReport.
  /// profitTrendPercent's own doc for the same rule).
  List<ReportInsight> financeInsights({
    required double netProfit,
    double? previousNetProfit,
  }) {
    final insights = <ReportInsight>[];
    insights.add(ReportInsight(netProfit >= 0
        ? 'The business was profitable this period.'
        : 'Expenses exceeded revenue this period.'));
    if (previousNetProfit != null && previousNetProfit != 0) {
      final change = ((netProfit - previousNetProfit) / previousNetProfit.abs()) * 100;
      final direction = change >= 0 ? 'up' : 'down';
      insights.add(ReportInsight('Net profit is $direction ${change.abs().toStringAsFixed(1)}% versus the previous period.'));
    }
    return insights;
  }

  /// Volume 10: "presented factually, never as a ranked comparison" —
  /// this deliberately produces observations about the TEAM as a whole
  /// (attendance rate, total contribution), never a "top performer"
  /// sentence naming one individual against others.
  ///
  /// **Bug fix (team/attendance audit):** the rate below is only ever
  /// computed over employee-days that actually have a marked
  /// attendance record — an employee never marked present/absent/late
  /// this period contributes (0, 0, 0) and so, correctly, doesn't skew
  /// the ratio itself. But with most of the roster untracked, a
  /// hypothetical "1 employee marked present, 9 never marked at all"
  /// period would still read "Team attendance was 100% this period" —
  /// technically accurate about the days that WERE tracked, but easy to
  /// misread as full-roster coverage. Rather than inventing a coverage
  /// threshold below which the insight is silently hidden (an arbitrary
  /// business rule this schema states nowhere), the sentence itself now
  /// names how much of the roster was actually tracked whenever that's
  /// less than the whole team, so the number can't be misread.
  List<ReportInsight> employeeInsights(List<EmployeePerformance> performance) {
    if (performance.isEmpty) return const [];
    final tracked = performance.where((p) => p.daysPresent + p.daysAbsent + p.daysLate > 0).toList();
    final totalDays = tracked.fold<int>(0, (s, p) => s + p.daysPresent + p.daysAbsent + p.daysLate);
    final presentDays = tracked.fold<int>(0, (s, p) => s + p.daysPresent);
    final insights = <ReportInsight>[];
    if (totalDays > 0) {
      final rate = (presentDays / totalDays) * 100;
      final coverage = tracked.length == performance.length
          ? ''
          : ' (based on ${tracked.length} of ${performance.length} employees with attendance recorded)';
      insights.add(ReportInsight('Team attendance was ${rate.toStringAsFixed(0)}% this period$coverage.'));
    }
    return insights;
  }

  String _formatHourRange(int hour) {
    String label(int h) {
      final period = h < 12 ? 'am' : 'pm';
      final display = h % 12 == 0 ? 12 : h % 12;
      return '$display$period';
    }
    return '${label(hour)}-${label((hour + 1) % 24)}';
  }
}
