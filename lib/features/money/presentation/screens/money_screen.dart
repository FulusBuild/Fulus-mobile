import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider, sessionPermissionsProvider, sessionProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_icons.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/mock_money_repository.dart';
import '../../domain/money_history_filter.dart';
import '../../domain/money_summary.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/breakdown_section.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/transaction_tile.dart';

/// Money workspace: balance first, then one compact view switch for
/// Overview / Transactions / Expenses. All values remain repository-backed.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  ReportPeriod? _builtForPeriod;
  late Future<double> _balanceFuture;
  late Future<MoneySummary> _summaryFuture;
  late Future<List<MoneyTransaction>> _transactionsFuture;
  int _selectedView = 0;

  void _load(ReportPeriod period) {
    final repo = ref.read(moneyRepositoryProvider);
    _builtForPeriod = period;
    final user = ref.read(sessionProvider);
    final currentAuthUserId = user?.id ?? '';
    final permissions = ref.read(sessionPermissionsProvider).value ?? const {};
    final canViewAllSales = user?.role == AuthRole.owner || permissions.contains(Permission.viewDashboardStats);
    _balanceFuture = repo.getAvailableBalance();
    _summaryFuture = repo.getSummary(period, currentAuthUserId: currentAuthUserId, canViewAllSales: canViewAllSales);
    _transactionsFuture = repo.getTransactions(period, currentAuthUserId: currentAuthUserId, canViewAllSales: canViewAllSales);
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await Future.wait([_balanceFuture, _summaryFuture, _transactionsFuture]);
  }

  void _toggleSimulatedError() {
    final repo = ref.read(moneyRepositoryProvider);
    if (repo is MockMoneyRepository) repo.debugSimulateFailure = !repo.debugSimulateFailure;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) {
        setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
      }
    });
    final period = ref.watch(moneyPeriodProvider);
    if (_builtForPeriod != period) _load(period);
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return FulusScreen(
      title: 'Money',
      applyPadding: false,
      actions: [
        if (kDebugMode)
          FulusIconButton(icon: FulusIcons.bugReport, tooltip: 'Simulate error (debug)', onPressed: _toggleSimulatedError),
        FulusIconButton(icon: FulusIcons.receipt, tooltip: 'Money history', onPressed: () => context.pushNamed('moneyHistory')),
        FulusIconButton(icon: FulusIcons.receipt, tooltip: 'Receipts', onPressed: () => context.pushNamed('receiptHistory')),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final inset = fulusHorizontalInset(context);
          final wide = constraints.maxWidth >= 760;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1120 : double.infinity),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.xxxl),
                  children: [
                    FutureBuilder<double>(
                      future: _balanceFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return _SectionError(onRetry: _refresh, message: "Couldn't load your balance.");
                        if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: _BalanceHeroSkeleton());
                        return _BalanceHero(balance: snapshot.data!, currencySymbol: currencySymbol);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const MoneyPeriodFilterBar(),
                    const SizedBox(height: AppSpacing.md),
                    _MoneyViewTabs(
                      selectedIndex: _selectedView,
                      onChanged: (index) => setState(() => _selectedView = index),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_selectedView == 0)
                      _OverviewView(
                        summaryFuture: _summaryFuture,
                        transactionsFuture: _transactionsFuture,
                        currencySymbol: currencySymbol,
                        onRefresh: _refresh,
                      )
                    else if (_selectedView == 1)
                      _TransactionsView(
                        transactionsFuture: _transactionsFuture,
                        currencySymbol: currencySymbol,
                        onRefresh: _refresh,
                      )
                    else
                      _ExpensesView(
                        transactionsFuture: _transactionsFuture,
                        currencySymbol: currencySymbol,
                        onRefresh: _refresh,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoneyViewTabs extends StatelessWidget {
  const _MoneyViewTabs({required this.selectedIndex, required this.onChanged});
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = ['Overview', 'Transactions', 'Expenses'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceAltOf(context), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: selectedIndex == i,
                label: labels[i],
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: selectedIndex == i ? AppColors.surfaceOf(context) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      boxShadow: selectedIndex == i ? AppElevation.subtleOf(context) : null,
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: AppTypography.label.copyWith(
                        color: selectedIndex == i ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context),
                        fontWeight: selectedIndex == i ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.summaryFuture, required this.transactionsFuture, required this.currencySymbol, required this.onRefresh});
  final Future<MoneySummary> summaryFuture;
  final Future<List<MoneyTransaction>> transactionsFuture;
  final String currencySymbol;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _QuickActionsRow(),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<MoneySummary>(
          future: summaryFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _SectionError(
                onRetry: onRefresh,
                message: "Couldn't load this period's summary.",
                reassurance: 'Your recorded sales, income, and expenses are safe — this is only about showing the totals right now.',
              );
            }
            if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: _SummarySkeleton());
            return _SummarySection(
              summary: snapshot.data!,
              currencySymbol: currencySymbol,
              onBreakdownRowTap: (row) => context.pushNamed(
                'moneyHistory',
                extra: MoneyHistoryFilterRequest(
                  type: row.type,
                  category: row.type == MoneyTransactionType.expense ? row.label : null,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        _RecentTransactions(transactionsFuture: transactionsFuture, currencySymbol: currencySymbol, onRefresh: onRefresh),
      ],
    );
  }
}

class _TransactionsView extends StatelessWidget {
  const _TransactionsView({required this.transactionsFuture, required this.currencySymbol, required this.onRefresh});
  final Future<List<MoneyTransaction>> transactionsFuture;
  final String currencySymbol;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => _TransactionFeed(
        title: 'Transactions',
        transactionsFuture: transactionsFuture,
        currencySymbol: currencySymbol,
        onRefresh: onRefresh,
        emptyHeadline: 'No transactions for this period.',
        emptyBody: 'Sales, income, expenses, and payments you record will appear here.',
      );
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView({required this.transactionsFuture, required this.currencySymbol, required this.onRefresh});
  final Future<List<MoneyTransaction>> transactionsFuture;
  final String currencySymbol;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MoneyTransaction>>(
      future: transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _SectionError(onRetry: onRefresh, message: "Couldn't load expenses.");
        if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]));
        final expenses = snapshot.data!.where((item) => item.type == MoneyTransactionType.expense).toList();
        final total = expenses.fold<double>(0, (sum, item) => sum + item.amount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FulusStatCard(
              label: 'Expenses',
              value: formatMoney(total, symbol: currencySymbol),
              valueColor: AppColors.errorOf(context),
              trendLabel: '${expenses.length} transaction${expenses.length == 1 ? '' : 's'}',
            ),
            const SizedBox(height: AppSpacing.lg),
            if (expenses.isEmpty)
              const FulusEmptyState(icon: FulusIcons.payments, headline: 'No expenses for this period.', body: 'Expenses you record will appear here.')
            else
              _TransactionCard(items: expenses, currencySymbol: currencySymbol),
            const SizedBox(height: AppSpacing.lg),
            FulusQuickAction(icon: FulusIcons.remove, label: 'Add expense', onTap: () => context.pushNamed('moneyAddExpense')),
          ],
        );
      },
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.transactionsFuture, required this.currencySymbol, required this.onRefresh});
  final Future<List<MoneyTransaction>> transactionsFuture;
  final String currencySymbol;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FulusSectionHeader(title: 'Recent transactions', action: 'See all', onActionTap: () => context.pushNamed('moneyHistory')),
          _TransactionFeed(
            transactionsFuture: transactionsFuture,
            currencySymbol: currencySymbol,
            onRefresh: onRefresh,
            limit: 5,
            emptyHeadline: 'Nothing recorded for this period.',
            emptyBody: 'Sales, income, and expenses you record will show up here.',
          ),
        ],
      );
}

class _TransactionFeed extends StatelessWidget {
  const _TransactionFeed({required this.transactionsFuture, required this.currencySymbol, required this.onRefresh, required this.emptyHeadline, required this.emptyBody, this.title, this.limit});
  final String? title;
  final Future<List<MoneyTransaction>> transactionsFuture;
  final String currencySymbol;
  final VoidCallback onRefresh;
  final String emptyHeadline;
  final String emptyBody;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MoneyTransaction>>(
      future: transactionsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _SectionError(onRetry: onRefresh, message: "Couldn't load transactions.");
        if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]));
        final items = limit == null ? snapshot.data! : snapshot.data!.take(limit!).toList();
        if (items.isEmpty) return FulusEmptyState(icon: FulusIcons.receipt, headline: emptyHeadline, body: emptyBody);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              FulusSectionHeader(title: title!, action: 'See all', onActionTap: () => context.pushNamed('moneyHistory')),
              const SizedBox(height: AppSpacing.sm),
            ],
            _TransactionCard(items: items, currencySymbol: currencySymbol),
          ],
        );
      },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.items, required this.currencySymbol});
  final List<MoneyTransaction> items;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) => FulusCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const FulusListDivider(),
              MoneyTransactionTile(
                transaction: items[i],
                currencySymbol: currencySymbol,
                onTap: () => context.pushNamed('moneyTransactionDetail', pathParameters: {'id': items[i].id}, extra: items[i]),
              ),
            ],
          ],
        ),
      );
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.currencySymbol});
  final double balance;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(gradient: AppGradients.heroOf(context), borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: AppElevation.liftOf(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Available balance', style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withValues(alpha: 0.7))),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(formatMoney(balance, symbol: currencySymbol), style: AppTypography.display.copyWith(color: AppColors.onPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Net of every sale, expense, and payment recorded', style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withValues(alpha: 0.7))),
        ]),
      );
}

class _BalanceHeroSkeleton extends StatelessWidget {
  const _BalanceHeroSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(color: AppColors.surfaceAltOf(context), borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [FulusSkeletonBox(width: 130, height: 14), SizedBox(height: AppSpacing.md), FulusSkeletonBox(width: 210, height: 36)]),
      );
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (icon: FulusIcons.add, label: 'Add income', onTap: () => context.pushNamed('moneyAddIncome')),
      (icon: FulusIcons.remove, label: 'Add expense', onTap: () => context.pushNamed('moneyAddExpense')),
      (icon: FulusIcons.customers, label: 'Customers', onTap: () => context.pushNamed('moneyCustomers')),
      (icon: FulusIcons.localShipping, label: 'Suppliers', onTap: () => context.pushNamed('moneySuppliers')),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: columns == 2 ? 1.8 : 1.25,
          ),
          itemBuilder: (context, index) => FulusQuickAction(icon: actions[index].icon, label: actions[index].label, onTap: actions[index].onTap),
        );
      },
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary, required this.currencySymbol, this.onBreakdownRowTap});
  final MoneySummary summary;
  final String currencySymbol;
  final ValueChanged<CategoryTotal>? onBreakdownRowTap;

  @override
  Widget build(BuildContext context) {
    final net = summary.net;
    final trendUp = net >= summary.previousNet;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 520;
        final cards = [
          Expanded(child: FulusStatCard(label: 'Money in', value: formatMoney(summary.moneyIn, symbol: currencySymbol), valueColor: AppColors.primaryOf(context))),
          Expanded(child: FulusStatCard(label: 'Money out', value: formatMoney(summary.moneyOut, symbol: currencySymbol), valueColor: AppColors.errorOf(context))),
        ];
        return horizontal ? Row(children: [cards[0], const SizedBox(width: AppSpacing.md), cards[1]]) : Column(children: [cards[0], const SizedBox(height: AppSpacing.sm), cards[1]]);
      }),
      const SizedBox(height: AppSpacing.md),
      FulusStatCard(label: 'Net', value: formatMoney(net, symbol: currencySymbol, showSign: true), valueColor: net >= 0 ? AppColors.primaryOf(context) : AppColors.errorOf(context), trend: trendUp ? FulusTrend.up : FulusTrend.down, trendLabel: 'vs previous period'),
      const SizedBox(height: AppSpacing.lg),
      MoneyBreakdownSection(title: 'Money in breakdown', rows: summary.incomeBreakdown, currencySymbol: currencySymbol, amountColor: AppColors.primaryOf(context), onRowTap: onBreakdownRowTap),
      MoneyBreakdownSection(title: 'Money out breakdown', rows: summary.expenseBreakdown, currencySymbol: currencySymbol, onRowTap: onBreakdownRowTap),
    ]);
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();
  @override
  Widget build(BuildContext context) => const Column(children: [Row(children: [Expanded(child: FulusStatCardSkeleton()), SizedBox(width: AppSpacing.md), Expanded(child: FulusStatCardSkeleton())]), SizedBox(height: AppSpacing.md), FulusStatCardSkeleton()]);
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry, this.reassurance});
  final String message;
  final String? reassurance;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => FulusErrorState(message: message, reassurance: reassurance, onRetry: onRetry);
}
