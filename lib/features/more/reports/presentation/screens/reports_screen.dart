import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/export/export_metadata.dart';
import '../../../../../core/export/export_service.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/finance_stats.dart';
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

  // Fetched once per period change rather than inline in build(): a
  // Future created directly inside build() is a new Future on every
  // rebuild, which resets every FutureBuilder below back to its loading
  // state — including on rebuilds that have nothing to do with the
  // report data (e.g. this screen rebuilding for an unrelated reason
  // higher in the tree). Caching here means these only refetch when
  // [_periodKind] genuinely changes.
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
    _salesFuture = repo.getSalesReport(period);
    _inventoryFuture = repo.getInventoryReport();
    _customersFuture = repo.getCustomerReport(period);
    _financeFuture = repo.getFinanceReport(period);
    _employeesFuture = repo.getEmployeeReport(period);
    // FinanceStatsRepository, not ReportsRepository — the confirmed
    // inflow bug was fixed at its source there (see
    // CashFlowReport.customerRepaymentsInflow's own doc comment), not
    // duplicated into a second implementation here. getCashFlow needs
    // a locationId reports_repository_impl.dart's own methods don't —
    // chained off the same activeLocationIdProvider Stock/Sell already
    // read from, rather than adding a second, competing notion of
    // "current location" to this screen.
    _cashFlowFuture = ref.read(activeLocationIdProvider.future).then(
          (locationId) => ref.read(financeStatsRepositoryProvider).getCashFlow(
                dateFrom: period.start,
                dateTo: period.end,
                locationId: locationId,
              ),
        );
  }

  /// One retry for every tab's data (including cash flow) rather than
  /// independent ones per fetch — matches [_loadAll] itself, which
  /// already fetches everything together. A tab whose data loaded fine
  /// re-fetches unnecessarily when a sibling tab retries, but that's
  /// one cheap extra read, not a user-visible cost, and keeps this
  /// screen's one existing "how do I reload" mechanism the only one
  /// instead of adding more.
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
      // Cancelling the picker leaves whatever was selected before —
      // never silently falls through to "Today", which would be a
      // surprising, unrequested period change.
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

  /// Sends the owner into Money History pre-filtered to exactly the
  /// transactions behind whichever stat card they tapped — Volume 8's
  /// "each row tappable through to the actual list of transactions
  /// behind it" rule, reused here rather than building Reports its own
  /// second transaction-list screen. Sets Money's own shared period
  /// state ([moneyPeriodKindProvider]/[customMoneyRangeProvider]) to
  /// match this screen's period first, so History opens already
  /// showing the same date range the tapped number was computed over.
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
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('CSV'),
            subtitle: const Text('Open in a spreadsheet'),
            onTap: () => Navigator.of(sheetContext).pop(ExportFormat.csv),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF'),
            subtitle: const Text('Share a printable summary'),
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

  /// Built from whichever `Future` the currently-open tab already
  /// depends on — by the time the export action is reachable that tab
  /// has necessarily already loaded (its own `FutureBuilder` would
  /// still be showing a spinner otherwise), so awaiting it again here
  /// resolves immediately rather than re-fetching.
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
            ['Stock value', formatMoney(r.totalStockValue, symbol: currencySymbol)],
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
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          FulusIconButton(icon: Icons.ios_share, tooltip: 'Export', onPressed: _export),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Sales'),
            Tab(text: 'Inventory'),
            Tab(text: 'Customers'),
            Tab(text: 'Finance'),
            Tab(text: 'Team'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SegmentedButton<ReportPeriodKind>(
              segments: [
                const ButtonSegment(value: ReportPeriodKind.today, label: Text('Today')),
                const ButtonSegment(value: ReportPeriodKind.thisWeek, label: Text('This week')),
                const ButtonSegment(value: ReportPeriodKind.thisMonth, label: Text('This month')),
                ButtonSegment(
                  value: ReportPeriodKind.custom,
                  label: Text(_customRange == null
                      ? 'Custom'
                      : '${formatRelativeDay(_customRange!.start)} – ${formatRelativeDay(_customRange!.end)}'),
                ),
              ],
              selected: {_periodKind},
              onSelectionChanged: _onPeriodSelectionChanged,
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

/// [onTap], when supplied, renders a trailing chevron and makes the
/// whole row tappable — gap-closure pass ("Reports drill-down").
/// `onTap: null` (the default) renders exactly as before: a plain,
/// non-interactive figure, for the several stat cards (Gross profit,
/// Net profit, Cost of goods sold...) that are computed aggregates
/// with no single underlying list to drill into.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: radius, boxShadow: AppElevation.cardOf(context)),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
                ),
                Text(
                  value,
                  style:
                      AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.chevron_right, size: AppIconSize.compact, color: AppColors.textSecondaryOf(context)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared loading/error handling every tab below delegates to, so the
/// hasError/hasData/empty branching only needs writing once. [isEmpty]
/// is evaluated only once data has actually arrived.
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
        if (!snap.hasData) {
          return const FulusLoadingIndicator();
        }
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
          // Was onOpenMoneyHistory — that screen has no receipt
          // number, cashier, or void/refund status, which is exactly
          // what "where did this number come from" needs. Money
          // History is still one tap away from here if wanted (below).
          onTap: () => _openTransactions(context),
        ),
        _StatCard(
          label: 'Sales',
          value: '${r.totalSalesCount}',
          onTap: () => _openTransactions(context),
        ),
        _StatCard(label: 'Discounts given', value: formatMoney(r.totalDiscount, symbol: currencySymbol)),
        if (r.topProducts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
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
        _StatCard(
          label: 'Stock value',
          value: formatMoney(r.totalStockValue, symbol: currencySymbol),
          onTap: () => context.go('/stock'),
        ),
        _StatCard(label: 'Low stock', value: '${r.lowStockCount}', onTap: () => context.go('/stock')),
        _StatCard(label: 'Out of stock', value: '${r.outOfStockCount}', onTap: () => context.go('/stock')),
        _StatCard(label: 'Total products', value: '${r.totalProducts}', onTap: () => context.go('/stock')),
        if (r.notSoldInThirtyDays.isNotEmpty)
          _StatCard(
            label: 'Not sold in 30 days',
            value: '${r.notSoldInThirtyDays.length}',
            onTap: () => _showNotSold(context, r.notSoldInThirtyDays),
          ),
      ]),
    );
  }
}

class _CustomersTab extends StatelessWidget {
  const _CustomersTab({
    required this.future,
    required this.currencySymbol,
    required this.onRetry,
  });
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
        _StatCard(
          label: 'Outstanding credit',
          value: formatMoney(r.totalOutstandingCredit, symbol: currencySymbol),
          onTap: () => context.pushNamed('moneyCustomers'),
        ),
        _StatCard(
          label: 'New customers',
          value: '${r.newCustomersThisPeriod}',
          onTap: () => context.pushNamed('moneyCustomers'),
        ),
        for (final c in r.topCustomers.take(5))
          _StatCard(
            label: c.customerName,
            value: formatMoney(c.totalSpend, symbol: currencySymbol),
            onTap: () => context.pushNamed('moneyCustomerProfile', pathParameters: {'id': c.customerId}),
          ),
      ]),
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({
    required this.future,
    required this.cashFlowFuture,
    required this.currencySymbol,
    required this.onRetry,
    required this.onOpenMoneyHistory,
  });
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
          _StatCard(
            label: 'Revenue',
            value: formatMoney(r.totalRevenue, symbol: currencySymbol),
            onTap: () => onOpenMoneyHistory(),
          ),
          _StatCard(label: 'Cost of goods sold', value: formatMoney(r.totalCostOfGoodsSold, symbol: currencySymbol)),
          _StatCard(label: 'Gross profit', value: formatMoney(r.grossProfit, symbol: currencySymbol)),
          _StatCard(
            label: 'Expenses',
            value: formatMoney(r.totalExpenses, symbol: currencySymbol),
            onTap: () => onOpenMoneyHistory(type: MoneyTransactionType.expense),
          ),
          _StatCard(label: 'Net profit', value: formatMoney(r.netProfit, symbol: currencySymbol)),
          if (trend != null)
            _StatCard(label: 'Vs. last period', value: '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%'),
          if (r.expenseBreakdown.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Expenses by category', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
            for (final e in r.expenseBreakdown)
              _StatCard(
                label: e.category,
                value: formatMoney(e.total, symbol: currencySymbol),
                onTap: () => onOpenMoneyHistory(type: MoneyTransactionType.expense, category: e.category),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text('Cash flow', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          // Own FutureBuilder, not folded into the FinanceReport one
          // above — money actually moving (this) and profit already
          // earned (everything above) are different questions with
          // different sources; a slow or failed cash-flow fetch
          // shouldn't blank out a Finance tab that otherwise loaded
          // fine.
          FutureBuilder<CashFlowReport>(
            future: cashFlowFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  "Couldn't load cash flow for this period.",
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final cf = snap.data!;
              return Column(
                children: [
                  _StatCard(label: 'Money in', value: formatMoney(cf.inflow, symbol: currencySymbol)),
                  _StatCard(
                    label: '· from sales',
                    value: formatMoney(cf.salesInflow, symbol: currencySymbol),
                  ),
                  _StatCard(
                    label: '· from customer repayments',
                    value: formatMoney(cf.customerRepaymentsInflow, symbol: currencySymbol),
                  ),
                  if (cf.manualIncomeInflow > 0)
                    _StatCard(
                      label: '· other income',
                      value: formatMoney(cf.manualIncomeInflow, symbol: currencySymbol),
                    ),
                  _StatCard(label: 'Money out', value: formatMoney(cf.outflow, symbol: currencySymbol)),
                  _StatCard(
                    label: '· expenses',
                    value: formatMoney(cf.expensesOutflow, symbol: currencySymbol),
                  ),
                  if (cf.supplierPaymentsOutflow > 0)
                    _StatCard(
                      label: '· supplier payments',
                      value: formatMoney(cf.supplierPaymentsOutflow, symbol: currencySymbol),
                    ),
                  _StatCard(label: 'Net cash flow', value: formatMoney(cf.netCashFlow, symbol: currencySymbol)),
                ],
              );
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
          _StatCard(
            label: p.employeeName,
            value: '${p.daysPresent} present, ${p.daysAbsent} absent',
            onTap: () => context.pushNamed('moreEmployeeDetail', pathParameters: {'employeeId': p.employeeId}),
          ),
      ]),
    );
  }
}
