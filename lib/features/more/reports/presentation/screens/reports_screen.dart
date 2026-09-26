import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/export/export_metadata.dart';
import '../../../../../core/export/export_service.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/finance_stats.dart';
import '../../../../../domain/entities/permission.dart';
import '../../../../../domain/entities/report.dart';
import '../../../../../domain/usecases/reports_engine.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../money/domain/money_history_filter.dart';
import '../../../../money/domain/money_transaction.dart';
import '../../../../money/presentation/providers/money_providers.dart'
    show moneyCurrencySymbolProvider, moneyPeriodKindProvider, customMoneyRangeProvider, businessNameProvider;
import '../../../../money/presentation/utils/money_format.dart';

/// Volume 10: one shared period selector above five categories, not
/// eleven screens. Sales/Finance/Employees are period-scoped; Inventory
/// is a live snapshot (no period selector applies to it, matching
/// ReportsRepository.getInventoryReport's own signature taking none).
///
/// Gap fixes in this pass:
/// - Currency was hardcoded to '₦' in every stat card (~15 call sites)
///   — now reads [moneyCurrencySymbolProvider], the same source every
///   other screen in this app uses.
/// - No tab had an error branch — a failed fetch spun its
///   [CircularProgressIndicator] forever with no message and no way
///   out. Every tab now checks `snapshot.hasError` first.
/// - No tab had an empty state — Volume 14 catalogs "No reports yet" as
///   one of its eleven illustrated empty states; a brand-new business
///   was instead shown a wall of "₦0.00" stat cards.
/// - Scaffold/StatCard used the flat, light-only `backgroundLight`/
///   `surfaceLight` constants — this screen ignored dark/system theme
///   entirely. Now uses the same brightness-aware `...Of(context)`
///   accessors the rest of the app uses.
///
/// Gap-closure pass ("Reports drill-down / export / custom range"):
/// - The period selector gains a fourth "Custom" option
///   (`showDateRangePicker`, the same mechanism `MoneyPeriodFilterBar`
///   already uses for Money's own equivalent selector) —
///   `ReportsEngine.resolvePeriod(ReportPeriodKind.custom, ...)`
///   already supported this; nothing above it ever exposed it.
/// - An Export action (real — `ExportService`, the same CSV/PDF/Share
///   Sheet mechanism Money History and Backup already use) exports
///   whichever tab is currently open.
/// - Every stat card and list row that has a real, specific place to
///   go now goes there: a top product opens its own Product Detail
///   screen, a top customer opens their Customer Profile, an employee
///   row opens Employee Detail, and the money-figure stat cards open
///   Money History pre-filtered to exactly the transactions behind
///   that number — Volume 8's own "each row tappable through to the
///   actual list of transactions behind it" rule, extended here from
///   Money's own screens to Reports.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  ReportPeriodKind _periodKind = ReportPeriodKind.today;
  DateTimeRange? _customRange;
  static const _engine = ReportsEngine();

  ReportPeriod get _period {
    if (_periodKind == ReportPeriodKind.custom && _customRange != null) {
      return _engine.resolvePeriod(
        ReportPeriodKind.custom,
        customStart: _customRange!.start,
        customEnd: _customRange!.end,
      );
    }
    return _engine.resolvePeriod(_periodKind);
  }

  late Future<SalesReport> _salesFuture;
  late Future<InventoryReport> _inventoryFuture;
  late Future<CustomerReport> _customersFuture;
  late Future<FinanceReport> _financeFuture;
  late Future<EmployeeReport> _employeesFuture;
  late Future<CashFlowReport> _cashFlowFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    final repo = ref.read(reportsRepositoryProvider);
    final period = _period;
    final user = ref.read(sessionProvider);
    final permissions = ref.read(sessionPermissionsProvider).value ?? const {};
    final canViewAllSales = user?.role == AuthRole.owner || permissions.contains(Permission.viewDashboardStats);
    final locationFuture = ref.read(activeLocationIdProvider.future);
    _salesFuture = locationFuture.then((locationId) => repo.getSalesReport(
          period,
          currentAuthUserId: user?.id ?? '',
          canViewAllSales: canViewAllSales,
          locationId: locationId,
        ));
    _inventoryFuture = locationFuture.then((locationId) => repo.getInventoryReport(locationId: locationId));
    _customersFuture = locationFuture.then((locationId) => repo.getCustomerReport(period, locationId: locationId));
    _financeFuture = locationFuture.then((locationId) => repo.getFinanceReport(period, locationId: locationId));
    _employeesFuture = locationFuture.then((locationId) => repo.getEmployeeReport(period, locationId: locationId));
    _cashFlowFuture = locationFuture.then(
          (locationId) => ref.read(financeStatsRepositoryProvider).getCashFlow(
                dateFrom: period.start,
                dateTo: period.end,
                locationId: locationId,
              ),
        );
  }

  void _retry() => setState(_loadAll);

  Future<void> _onPeriodSelectionChanged(Set<ReportPeriodKind> selection) async {
    final kind = selection.first;
    if (kind == ReportPeriodKind.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _customRange = picked;
        _periodKind = ReportPeriodKind.custom;
        _loadAll();
      });
      return;
    }
    setState(() {
      _periodKind = kind;
      _loadAll();
    });
  }

  void _openMoneyHistory({MoneyTransactionType? type, String? category}) {
    ref.read(moneyPeriodKindProvider.notifier).state = _periodKind;
    ref.read(customMoneyRangeProvider.notifier).state =
        _periodKind == ReportPeriodKind.custom ? _customRange : null;
    context.pushNamed(
      'moneyHistory',
      extra: MoneyHistoryFilterRequest(type: type, category: category),
    );
  }

  Future<void> _export() async {
    final format = await showFulusBottomSheet<ExportFormat>(
      context: context,
      title: 'Export report',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusActionTile(
            icon: FulusIcons.tableChart,
            label: 'CSV',
            subtitle: 'Open in a spreadsheet',
            onTap: () => Navigator.of(sheetContext).pop(ExportFormat.csv),
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusActionTile(
            icon: FulusIcons.pictureAsPdf,
            label: 'PDF',
            subtitle: 'Share a printable summary',
            onTap: () => Navigator.of(sheetContext).pop(ExportFormat.pdf),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final currencySymbol = ref.read(moneyCurrencySymbolProvider).value ?? '₦';
    final businessName = ref.read(businessNameProvider).value ?? 'Fulus';
    try {
      final payload = await _buildExportPayload(currencySymbol);
      final dateRangeLabel = '${formatRelativeDay(_period.start)} – ${formatRelativeDay(_period.end)}';
      await ref.read(exportServiceProvider).export(
            format: format,
            fileName: 'report-${payload.name}-${DateTime.now().millisecondsSinceEpoch}',
            title: payload.title,
            subtitle: dateRangeLabel,
            metadata: ExportMetadata(
              businessName: businessName,
              reportName: payload.title,
              dateRangeLabel: dateRangeLabel,
              generatedAt: DateTime.now(),
              currencySymbol: currencySymbol,
            ),
            headers: payload.headers,
            rows: payload.rows,
          );
    } catch (_) {
      if (mounted) showFulusSnackbar(context, message: "Couldn't export right now. Please try again.");
    }
  }

  Future<_ExportPayload> _buildExportPayload(String currencySymbol) async {
    switch (_tabs.index) {
      case 0:
        final r = await _salesFuture;
        return _ExportPayload(
          name: 'sales',
          title: 'Sales report',
          headers: const ['Metric', 'Value'],
          rows: [
            ['Revenue', formatMoney(r.totalRevenue, symbol: currencySymbol)],
            ['Sales', '${r.totalSalesCount}'],
            ['Discounts given', formatMoney(r.totalDiscount, symbol: currencySymbol)],
            ['Tax collected', formatMoney(r.totalTax, symbol: currencySymbol)],
            for (final p in r.topProducts)
              ['Top product — ${p.productName}', formatMoney(p.revenue, symbol: currencySymbol)],
          ],
        );
      case 1:
        final r = await _inventoryFuture;
        return _ExportPayload(
          name: 'inventory',
          title: 'Inventory report',
          headers: const ['Metric', 'Value'],
          rows: [
            ['Stock value (at cost)', formatMoney(r.totalStockValue, symbol: currencySymbol)],
            ['Low stock', '${r.lowStockCount}'],
            ['Out of stock', '${r.outOfStockCount}'],
            ['Total products', '${r.totalProducts}'],
            ['Not sold in 30 days', '${r.notSoldInThirtyDays.length}'],
          ],
        );
      case 2:
        final r = await _customersFuture;
        return _ExportPayload(
          name: 'customers',
          title: 'Customers report',
          headers: const ['Metric', 'Value'],
          rows: [
            ['Outstanding credit', formatMoney(r.totalOutstandingCredit, symbol: currencySymbol)],
            ['New customers', '${r.newCustomersThisPeriod}'],
            for (final c in r.topCustomers)
              ['Top customer — ${c.customerName}', formatMoney(c.totalSpend, symbol: currencySymbol)],
          ],
        );
      case 3:
        final r = await _financeFuture;
        return _ExportPayload(
          name: 'finance',
          title: 'Finance report',
          headers: const ['Metric', 'Value'],
          rows: [
            ['Revenue', formatMoney(r.totalRevenue, symbol: currencySymbol)],
            ['Cost of goods sold', formatMoney(r.totalCostOfGoodsSold, symbol: currencySymbol)],
            ['Gross profit', formatMoney(r.grossProfit, symbol: currencySymbol)],
            ['Expenses', formatMoney(r.totalExpenses, symbol: currencySymbol)],
            ['Net profit', formatMoney(r.netProfit, symbol: currencySymbol)],
            for (final e in r.expenseBreakdown)
              ['Expense — ${e.category}', formatMoney(e.total, symbol: currencySymbol)],
          ],
        );
      default:
        final r = await _employeesFuture;
        return _ExportPayload(
          name: 'team',
          title: 'Team report',
          headers: const ['Employee', 'Present', 'Absent', 'Late'],
          rows: [
            for (final p in r.performance) [p.employeeName, '${p.daysPresent}', '${p.daysAbsent}', '${p.daysLate}'],
          ],
        );
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) setState(_loadAll);
    });
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Reports',
      backgroundColor: const Color(0xFF061B3A),
      headerBackgroundColor: const Color(0xFF061B3A),
      subtitle: 'Understand sales, stock, customers, money and team activity',
      actions: [
        FulusIconButton(icon: Icons.ios_share, tooltip: 'Export report', onPressed: _export),
      ],
      applyPadding: false,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(fulusHorizontalInset(context), AppSpacing.sm, fulusHorizontalInset(context), AppSpacing.xs),
            child: SizedBox(
              height: 126,
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 2.35,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ReportCategoryCard(label: 'Sales Report', icon: FulusIcons.reports, color: const Color(0xFF0BBE6E), onTap: () => setState(() => _tabs.animateTo(0))),
                  _ReportCategoryCard(label: 'Stock Report', icon: FulusIcons.stock, color: const Color(0xFF1677FF), onTap: () => setState(() => _tabs.animateTo(1))),
                  _ReportCategoryCard(label: 'Expense Report', icon: FulusIcons.receipt, color: const Color(0xFFFF8A00), onTap: () => setState(() => _tabs.animateTo(3))),
                  _ReportCategoryCard(label: 'Customer Report', icon: FulusIcons.customers, color: const Color(0xFF7B3FF2), onTap: () => setState(() => _tabs.animateTo(2))),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              fulusHorizontalInset(context),
              AppSpacing.xs,
              fulusHorizontalInset(context),
              AppSpacing.sm,
            ),
            child: FulusChipRow(
              children: [
                FulusChip(label: 'Today', selected: _periodKind == ReportPeriodKind.today, onTap: () => _onPeriodSelectionChanged({ReportPeriodKind.today})),
                FulusChip(label: 'This week', selected: _periodKind == ReportPeriodKind.thisWeek, onTap: () => _onPeriodSelectionChanged({ReportPeriodKind.thisWeek})),
                FulusChip(label: 'This month', selected: _periodKind == ReportPeriodKind.thisMonth, onTap: () => _onPeriodSelectionChanged({ReportPeriodKind.thisMonth})),
                FulusChip(label: _customRange == null ? 'Custom' : formatRelativeDay(_customRange!.start) + ' – ' + formatRelativeDay(_customRange!.end), selected: _periodKind == ReportPeriodKind.custom, onTap: () => _onPeriodSelectionChanged({ReportPeriodKind.custom})),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SalesTab(
                  future: _salesFuture,
                  currencySymbol: currencySymbol,
                  onRetry: _retry,
                  period: _period,
                ),
                _InventoryTab(future: _inventoryFuture, currencySymbol: currencySymbol, onRetry: _retry),
                _CustomersTab(
                  future: _customersFuture,
                  currencySymbol: currencySymbol,
                  onRetry: _retry,
                ),
                _FinanceTab(
                  future: _financeFuture,
                  cashFlowFuture: _cashFlowFuture,
                  currencySymbol: currencySymbol,
                  onRetry: _retry,
                  onOpenMoneyHistory: _openMoneyHistory,
                ),
                _EmployeesTab(future: _employeesFuture, onRetry: _retry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCategoryCard extends StatelessWidget {
  const _ReportCategoryCard({required this.label, required this.icon, required this.color, required this.onTap});
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color, borderRadius: BorderRadius.circular(10),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(children: [Icon(icon, color: Colors.white, size: 24), const SizedBox(width: AppSpacing.sm), Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)))])
    )),
  );
}

class _ExportPayload {
  const _ExportPayload({required this.name, required this.title, required this.headers, required this.rows});
  final String name;
  final String title;
  final List<String> headers;
  final List<List<Object?>> rows;
}

class _ReportScaffold extends StatelessWidget {
  const _ReportScaffold({required this.insights, required this.children});
  final List<ReportInsight> insights;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        ...children,
        if (insights.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('What this means', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: AppSpacing.sm),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '• ${insight.text}',
                style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FulusStatCard(
      label: label,
      value: value,
      onTap: onTap,
    );
  }
}

class _ReportTabBuilder<T> extends StatelessWidget {
  const _ReportTabBuilder({
    required this.future,
    required this.onRetry,
    required this.isEmpty,
    required this.emptyHeadline,
    required this.emptyBody,
    required this.builder,
  });

  final Future<T> future;
  final VoidCallback onRetry;
  final bool Function(T data) isEmpty;
  final String emptyHeadline;
  final String emptyBody;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return FulusErrorState(
            message: "Couldn't load this report.",
            reassurance: 'Nothing recorded was changed — this is only about loading the numbers.',
            onRetry: onRetry,
          );
        }
        if (!snap.hasData) return const FulusLoadingIndicator();
        final data = snap.data as T;
        if (isEmpty(data)) {
          return FulusEmptyState(
            icon: Icons.bar_chart_outlined,
            headline: emptyHeadline,
            body: emptyBody,
          );
        }
        return builder(context, data);
      },
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({
    required this.future,
    required this.currencySymbol,
    required this.onRetry,
    required this.period,
  });
  final Future<SalesReport> future;
  final String currencySymbol;
  final VoidCallback onRetry;
  final ReportPeriod period;

  void _openTransactions(BuildContext context) {
    context.pushNamed('moreReportsSalesTransactions', extra: period);
  }

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<SalesReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.totalSalesCount == 0,
      emptyHeadline: 'No sales in this period.',
      emptyBody: 'Sales you record will show up here, broken down by product.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        _StatCard(
          label: 'Revenue',
          value: formatMoney(r.totalRevenue, symbol: currencySymbol),
          onTap: () => _openTransactions(context),
        ),
        _StatCard(
          label: 'Sales',
          value: '${r.totalSalesCount}',
          onTap: () => _openTransactions(context),
        ),
        _StatCard(label: 'Discounts given', value: formatMoney(r.totalDiscount, symbol: currencySymbol)),
        const SizedBox(height: AppSpacing.sm),
        _SalesChart(report: r, currencySymbol: currencySymbol, period: period),
        if (r.topProducts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Top products', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          for (final p in r.topProducts.take(5))
            _StatCard(
              label: p.productName,
              value: formatMoney(p.revenue, symbol: currencySymbol),
              onTap: () => context.pushNamed('stockProductDetail', pathParameters: {'productId': p.productId}),
            ),
        ],
      ]),
    );
  }
}

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.report, required this.currencySymbol, required this.period});
  final SalesReport report;
  final String currencySymbol;
  final ReportPeriod period;

  @override
  Widget build(BuildContext context) {
    final oneDay = period.start.year == period.end.year &&
        period.start.month == period.end.month &&
        period.start.day == period.end.day;
    final buckets = <String, double>{};

    if (oneDay) {
      for (final point in report.byHour) {
        buckets['${point.hour.toString().padLeft(2, '0')}:00'] = point.total;
      }
      for (var hour = 0; hour < 24; hour++) {
        buckets.putIfAbsent('${hour.toString().padLeft(2, '0')}:00', () => 0);
      }
    } else {
      for (final sale in report.transactions) {
        final local = sale.saleDate.toLocal();
        final key = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
        buckets[key] = (buckets[key] ?? 0) + sale.total;
      }
      if (buckets.isEmpty) {
        var cursor = DateTime(period.start.year, period.start.month, period.start.day);
        final end = DateTime(period.end.year, period.end.month, period.end.day);
        while (!cursor.isAfter(end)) {
          buckets['${cursor.day.toString().padLeft(2, '0')}/${cursor.month.toString().padLeft(2, '0')}'] = 0;
          cursor = cursor.add(const Duration(days: 1));
        }
      }
    }

    final labels = buckets.keys.toList();
    final values = buckets.values.toList();
    final maxValue = values.fold<double>(0, (max, value) => value > max ? value : max);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppElevation.cardOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            oneDay ? 'Sales by hour' : 'Sales trend',
            style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            oneDay ? 'Revenue recorded throughout today.' : 'Revenue recorded across the selected period.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 190,
            child: _SalesChartPainterWidget(
              labels: labels,
              values: values,
              maxValue: maxValue,
              currencySymbol: currencySymbol,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesChartPainterWidget extends StatelessWidget {
  const _SalesChartPainterWidget({required this.labels, required this.values, required this.maxValue, required this.currencySymbol});
  final List<String> labels;
  final List<double> values;
  final double maxValue;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SalesChartPainter(
        labels: labels,
        values: values,
        maxValue: maxValue,
        textColor: AppColors.textSecondaryOf(context),
        lineColor: AppColors.primaryOf(context),
        fillColor: AppColors.primaryOf(context).withValues(alpha: 0.10),
        gridColor: AppColors.borderOf(context),
        currencySymbol: currencySymbol,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SalesChartPainter extends CustomPainter {
  _SalesChartPainter({
    required this.labels,
    required this.values,
    required this.maxValue,
    required this.textColor,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.currencySymbol,
  });

  final List<String> labels;
  final List<double> values;
  final double maxValue;
  final Color textColor;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final String currencySymbol;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 52.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 30.0;
    final chart = Rect.fromLTWH(left, top, size.width - left - right, size.height - top - bottom);
    final textStyle = TextStyle(fontSize: 10, color: textColor);

    final gridPaint = Paint()..color = gridColor.withValues(alpha: 0.45)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * (i / 3);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maxValue * (i / 3);
      final label = value == 0 ? '0' : _compact(value);
      final tp = TextPainter(text: TextSpan(text: label, style: textStyle), textDirection: TextDirection.ltr)..layout(maxWidth: left - 6);
      tp.paint(canvas, Offset(left - tp.width - 6, y - tp.height / 2));
    }

    if (values.isEmpty) return;
    final count = values.length;
    final step = count <= 1 ? 0.0 : chart.width / (count - 1);
    final points = <Offset>[];
    for (var i = 0; i < count; i++) {
      final normalized = maxValue <= 0 ? 0.0 : values[i] / maxValue;
      points.add(Offset(chart.left + step * i, chart.bottom - normalized * chart.height));
    }

    final fillPath = Path()..moveTo(points.first.dx, chart.bottom);
    for (final point in points) fillPath.lineTo(point.dx, point.dy);
    fillPath.lineTo(points.last.dx, chart.bottom);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) linePath.lineTo(point.dx, point.dy);
    canvas.drawPath(linePath, Paint()..color = lineColor..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);

    final maxLabels = size.width < 500 ? 6 : 10;
    final labelEvery = count <= maxLabels ? 1 : (count / maxLabels).ceil();
    for (var i = 0; i < count; i += labelEvery) {
      final tp = TextPainter(text: TextSpan(text: labels[i], style: textStyle), textDirection: TextDirection.ltr)..layout();
      var x = points[i].dx - tp.width / 2;
      x = x.clamp(chart.left - tp.width / 2, chart.right - tp.width / 2).toDouble();
      tp.paint(canvas, Offset(x, chart.bottom + 7));
    }
  }

  String _compact(double value) {
    if (value >= 1000000) return '${currencySymbol}${(value / 1000000).toStringAsFixed(1)}m';
    if (value >= 1000) return '${currencySymbol}${(value / 1000).toStringAsFixed(0)}k';
    return '${currencySymbol}${value.toStringAsFixed(0)}';
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter oldDelegate) {
    return oldDelegate.labels != labels || oldDelegate.values != values || oldDelegate.maxValue != maxValue || oldDelegate.lineColor != lineColor;
  }
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab({required this.future, required this.currencySymbol, required this.onRetry});
  final Future<InventoryReport> future;
  final String currencySymbol;
  final VoidCallback onRetry;

  void _showNotSold(BuildContext context, List<String> names) {
    showFulusBottomSheet<void>(
      context: context,
      title: 'Not sold in 30 days',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final name in names)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(name, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(sheetContext))),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<InventoryReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.totalProducts == 0,
      emptyHeadline: 'No products yet.',
      emptyBody: 'Add products in Stock to see their value and status here.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        _StatCard(label: 'Stock value (at cost)', value: formatMoney(r.totalStockValue, symbol: currencySymbol), onTap: () => context.go('/stock')),
        _StatCard(label: 'Low stock', value: '${r.lowStockCount}', onTap: () => context.go('/stock')),
        _StatCard(label: 'Out of stock', value: '${r.outOfStockCount}', onTap: () => context.go('/stock')),
        _StatCard(label: 'Total products', value: '${r.totalProducts}', onTap: () => context.go('/stock')),
        if (r.notSoldInThirtyDays.isNotEmpty)
          _StatCard(label: 'Not sold in 30 days', value: '${r.notSoldInThirtyDays.length}', onTap: () => _showNotSold(context, r.notSoldInThirtyDays)),
      ]),
    );
  }
}

class _CustomersTab extends StatelessWidget {
  const _CustomersTab({required this.future, required this.currencySymbol, required this.onRetry});
  final Future<CustomerReport> future;
  final String currencySymbol;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<CustomerReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.newCustomersThisPeriod == 0 && r.totalOutstandingCredit == 0 && r.topCustomers.isEmpty,
      emptyHeadline: 'Nothing to report yet.',
      emptyBody: 'Customer activity — new customers, credit, and top spenders — will show up here.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        _StatCard(label: 'Outstanding credit', value: formatMoney(r.totalOutstandingCredit, symbol: currencySymbol), onTap: () => context.pushNamed('moneyCustomers')),
        _StatCard(label: 'New customers', value: '${r.newCustomersThisPeriod}', onTap: () => context.pushNamed('moneyCustomers')),
        for (final c in r.topCustomers.take(5))
          _StatCard(label: c.customerName, value: formatMoney(c.totalSpend, symbol: currencySymbol), onTap: () => context.pushNamed('moneyCustomerProfile', pathParameters: {'id': c.customerId})),
      ]),
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({required this.future, required this.cashFlowFuture, required this.currencySymbol, required this.onRetry, required this.onOpenMoneyHistory});
  final Future<FinanceReport> future;
  final Future<CashFlowReport> cashFlowFuture;
  final String currencySymbol;
  final VoidCallback onRetry;
  final void Function({MoneyTransactionType? type, String? category}) onOpenMoneyHistory;

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<FinanceReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.totalRevenue == 0 && r.totalExpenses == 0,
      emptyHeadline: 'No financial activity yet.',
      emptyBody: 'Revenue, cost of goods, and expenses for this period will show up here.',
      builder: (context, r) {
        final trend = r.profitTrendPercent;
        return _ReportScaffold(insights: r.insights, children: [
          _StatCard(label: 'Revenue', value: formatMoney(r.totalRevenue, symbol: currencySymbol), onTap: () => onOpenMoneyHistory()),
          _StatCard(label: 'Cost of goods sold', value: formatMoney(r.totalCostOfGoodsSold, symbol: currencySymbol)),
          _StatCard(label: 'Gross profit', value: formatMoney(r.grossProfit, symbol: currencySymbol)),
          _StatCard(label: 'Expenses', value: formatMoney(r.totalExpenses, symbol: currencySymbol), onTap: () => onOpenMoneyHistory(type: MoneyTransactionType.expense)),
          _StatCard(label: 'Net profit', value: formatMoney(r.netProfit, symbol: currencySymbol)),
          if (trend != null) _StatCard(label: 'Vs. last period', value: '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%'),
          if (r.expenseBreakdown.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Expenses by category', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
            for (final e in r.expenseBreakdown)
              _StatCard(label: e.category, value: formatMoney(e.total, symbol: currencySymbol), onTap: () => onOpenMoneyHistory(type: MoneyTransactionType.expense, category: e.category)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text('Cash flow', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          FutureBuilder<CashFlowReport>(
            future: cashFlowFuture,
            builder: (context, snap) {
              if (snap.hasError) return Text("Couldn't load cash flow for this period.", style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)));
              if (!snap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Center(child: CircularProgressIndicator()));
              final cf = snap.data!;
              return Column(children: [
                _StatCard(label: 'Money in', value: formatMoney(cf.inflow, symbol: currencySymbol)),
                _StatCard(label: '· from sales', value: formatMoney(cf.salesInflow, symbol: currencySymbol)),
                _StatCard(label: '· from customer repayments', value: formatMoney(cf.customerRepaymentsInflow, symbol: currencySymbol)),
                if (cf.manualIncomeInflow > 0) _StatCard(label: '· other income', value: formatMoney(cf.manualIncomeInflow, symbol: currencySymbol)),
                _StatCard(label: 'Money out', value: formatMoney(cf.outflow, symbol: currencySymbol)),
                _StatCard(label: '· expenses', value: formatMoney(cf.expensesOutflow, symbol: currencySymbol)),
                if (cf.supplierPaymentsOutflow > 0) _StatCard(label: '· supplier payments', value: formatMoney(cf.supplierPaymentsOutflow, symbol: currencySymbol)),
                _StatCard(label: 'Net cash flow', value: formatMoney(cf.netCashFlow, symbol: currencySymbol)),
              ]);
            },
          ),
        ]);
      },
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({required this.future, required this.onRetry});
  final Future<EmployeeReport> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<EmployeeReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.performance.isEmpty,
      emptyHeadline: 'No team activity yet.',
      emptyBody: 'Attendance and performance for your team will show up here.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        for (final p in r.performance)
          _StatCard(label: p.employeeName, value: '${p.daysPresent} present, ${p.daysAbsent} absent', onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': p.employeeId})),
      ]),
    );
  }
}
