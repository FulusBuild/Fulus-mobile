import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/report.dart';
import '../../../../../domain/usecases/reports_engine.dart';

/// Volume 10: one shared period selector above five categories, not
/// eleven screens. Sales/Finance/Employees are period-scoped; Inventory
/// is a live snapshot (no period selector applies to it, matching
/// ReportsRepository.getInventoryReport's own signature taking none).
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

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
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
                _SalesTab(future: _salesFuture),
                _InventoryTab(future: _inventoryFuture),
                _CustomersTab(future: _customersFuture),
                _FinanceTab(future: _financeFuture),
                _EmployeesTab(future: _employeesFuture),
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
          Text('What this means', style: AppTypography.heading),
          const SizedBox(height: AppSpacing.sm),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• ${insight.text}', style: AppTypography.body),
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
      decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body),
          Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.future});
  final Future<SalesReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SalesReport>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        return _ReportScaffold(insights: r.insights, children: [
          _StatCard(label: 'Revenue', value: '₦${r.totalRevenue.toStringAsFixed(2)}'),
          _StatCard(label: 'Sales', value: '${r.totalSalesCount}'),
          _StatCard(label: 'Discounts given', value: '₦${r.totalDiscount.toStringAsFixed(2)}'),
          if (r.topProducts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Top products', style: AppTypography.heading),
            for (final p in r.topProducts.take(5))
              _StatCard(label: p.productName, value: '₦${p.revenue.toStringAsFixed(2)}'),
          ],
        ]);
      },
    );
  }
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab({required this.future});
  final Future<InventoryReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InventoryReport>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        return _ReportScaffold(insights: r.insights, children: [
          _StatCard(label: 'Stock value', value: '₦${r.totalStockValue.toStringAsFixed(2)}'),
          _StatCard(label: 'Low stock', value: '${r.lowStockCount}'),
          _StatCard(label: 'Out of stock', value: '${r.outOfStockCount}'),
          _StatCard(label: 'Total products', value: '${r.totalProducts}'),
        ]);
      },
    );
  }
}

class _CustomersTab extends StatelessWidget {
  const _CustomersTab({required this.future});
  final Future<CustomerReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerReport>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        return _ReportScaffold(insights: r.insights, children: [
          _StatCard(label: 'Outstanding credit', value: '₦${r.totalOutstandingCredit.toStringAsFixed(2)}'),
          _StatCard(label: 'New customers', value: '${r.newCustomersThisPeriod}'),
          for (final c in r.topCustomers.take(5))
            _StatCard(label: c.customerName, value: '₦${c.totalSpend.toStringAsFixed(2)}'),
        ]);
      },
    );
  }
}

class _FinanceTab extends StatelessWidget {
  const _FinanceTab({required this.future});
  final Future<FinanceReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FinanceReport>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        final trend = r.profitTrendPercent;
        return _ReportScaffold(insights: r.insights, children: [
          _StatCard(label: 'Revenue', value: '₦${r.totalRevenue.toStringAsFixed(2)}'),
          _StatCard(label: 'Expenses', value: '₦${r.totalExpenses.toStringAsFixed(2)}'),
          _StatCard(label: 'Net profit', value: '₦${r.netProfit.toStringAsFixed(2)}'),
          if (trend != null)
            _StatCard(label: 'Vs. last period', value: '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%'),
        ]);
      },
    );
  }
}

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab({required this.future});
  final Future<EmployeeReport> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmployeeReport>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        return _ReportScaffold(insights: r.insights, children: [
          for (final p in r.performance)
            _StatCard(label: p.employeeName, value: '${p.daysPresent} present, ${p.daysAbsent} absent'),
        ]);
      },
    );
  }
}
