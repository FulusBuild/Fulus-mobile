import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/report.dart';
import '../../../../../domain/usecases/reports_engine.dart';
import '../../../../../shared/widgets/widgets.dart';
import '../../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;

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
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  ReportPeriodKind _periodKind = ReportPeriodKind.today;
  static const _engine = ReportsEngine();

  ReportPeriod get _period => _engine.resolvePeriod(_periodKind);

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
  }

  /// One retry for all five tabs rather than five independent ones —
  /// matches [_loadAll] itself, which already fetches all five
  /// together. A tab whose data loaded fine re-fetches unnecessarily
  /// when a sibling tab retries, but that's one cheap extra read, not a
  /// user-visible cost, and keeps this screen's one existing "how do I
  /// reload" mechanism the only one instead of adding five more.
  void _retry() => setState(_loadAll);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        title: const Text('Reports'),
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
              segments: const [
                ButtonSegment(value: ReportPeriodKind.today, label: Text('Today')),
                ButtonSegment(value: ReportPeriodKind.thisWeek, label: Text('This week')),
                ButtonSegment(value: ReportPeriodKind.thisMonth, label: Text('This month')),
              ],
              selected: {_periodKind},
              onSelectionChanged: (s) => setState(() {
                _periodKind = s.first;
                _loadAll();
              }),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SalesTab(future: _salesFuture, currencySymbol: currencySymbol, onRetry: _retry),
                _InventoryTab(future: _inventoryFuture, currencySymbol: currencySymbol, onRetry: _retry),
                _CustomersTab(future: _customersFuture, currencySymbol: currencySymbol, onRetry: _retry),
                _FinanceTab(future: _financeFuture, currencySymbol: currencySymbol, onRetry: _retry),
                _EmployeesTab(future: _employeesFuture, onRetry: _retry),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
          Text(
            value,
            style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
          ),
        ],
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
  const _SalesTab({required this.future, required this.currencySymbol, required this.onRetry});
  final Future<SalesReport> future;
  final String currencySymbol;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<SalesReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.totalSalesCount == 0,
      emptyHeadline: 'No sales in this period.',
      emptyBody: 'Sales you record will show up here, broken down by product.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        _StatCard(label: 'Revenue', value: '$currencySymbol${r.totalRevenue.toStringAsFixed(2)}'),
        _StatCard(label: 'Sales', value: '${r.totalSalesCount}'),
        _StatCard(label: 'Discounts given', value: '$currencySymbol${r.totalDiscount.toStringAsFixed(2)}'),
        if (r.topProducts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Top products', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          for (final p in r.topProducts.take(5))
            _StatCard(label: p.productName, value: '$currencySymbol${p.revenue.toStringAsFixed(2)}'),
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

  @override
  Widget build(BuildContext context) {
    return _ReportTabBuilder<InventoryReport>(
      future: future,
      onRetry: onRetry,
      isEmpty: (r) => r.totalProducts == 0,
      emptyHeadline: 'No products yet.',
      emptyBody: 'Add products in Stock to see their value and status here.',
      builder: (context, r) => _ReportScaffold(insights: r.insights, children: [
        _StatCard(label: 'Stock value', value: '$currencySymbol${r.totalStockValue.toStringAsFixed(2)}'),
        _StatCard(label: 'Low stock', value: '${r.lowStockCount}'),
        _StatCard(label: 'Out of stock', value: '${r.outOfStockCount}'),
        _StatCard(label: 'Total products', value: '${r.totalProducts}'),
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
        _StatCard(label: 'Outstanding credit', value: '$currencySymbol${r.totalOutstandingCredit.toStringAsFixed(2)}'),
        _StatCard(label: 'New customers', value: '${r.newCustomersThisPeriod}'),
        for (final c in r.topCustomers.take(5))
          _StatCard(label: c.customerName, value: '$currencySymbol${c.totalSpend.toStringAsFixed(2)}'),
      ]),
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({required this.future, required this.currencySymbol, required this.onRetry});
  final Future<FinanceReport> future;
  final String currencySymbol;
  final VoidCallback onRetry;

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
          _StatCard(label: 'Revenue', value: '$currencySymbol${r.totalRevenue.toStringAsFixed(2)}'),
          _StatCard(label: 'Cost of goods sold', value: '$currencySymbol${r.totalCostOfGoodsSold.toStringAsFixed(2)}'),
          _StatCard(label: 'Gross profit', value: '$currencySymbol${r.grossProfit.toStringAsFixed(2)}'),
          _StatCard(label: 'Expenses', value: '$currencySymbol${r.totalExpenses.toStringAsFixed(2)}'),
          _StatCard(label: 'Net profit', value: '$currencySymbol${r.netProfit.toStringAsFixed(2)}'),
          if (trend != null)
            _StatCard(label: 'Vs. last period', value: '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%'),
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
          _StatCard(label: p.employeeName, value: '${p.daysPresent} present, ${p.daysAbsent} absent'),
      ]),
    );
  }
}
