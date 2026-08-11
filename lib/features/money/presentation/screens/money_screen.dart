import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
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

/// Volume 8's Cash Flow screen — the Money tab's home. "Money In, Money
/// Out, and Net, for a selected period — one view, not a chart wall,"
/// plus the balance hero, quick actions, and a peek at recent
/// transactions with a way into the full history. See
/// `money_transaction.dart`'s doc comment for this feature's real-vs-
/// mock data boundary.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  ReportPeriod? _builtForPeriod;
  late Future<double> _balanceFuture;
  late Future<MoneySummary> _summaryFuture;
  late Future<List<MoneyTransaction>> _recentFuture;

  void _load(ReportPeriod period) {
    final repo = ref.read(moneyRepositoryProvider);
    _builtForPeriod = period;
    _balanceFuture = repo.getAvailableBalance();
    _summaryFuture = repo.getSummary(period);
    _recentFuture = repo.getTransactions(period).then((list) => list.take(5).toList());
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await Future.wait([_balanceFuture, _summaryFuture, _recentFuture]);
  }

  /// Debug-only affordance so this screen's error states are something
  /// a reviewer can actually trigger and see, not just code that never
  /// visibly runs. Gated on [kDebugMode] — never shown in a release
  /// build.
  void _toggleSimulatedError() {
    final repo = ref.read(moneyRepositoryProvider);
    if (repo is MockMoneyRepository) {
      repo.debugSimulateFailure = !repo.debugSimulateFailure;
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(moneyPeriodProvider);
    if (_builtForPeriod != period) {
      _load(period);
    }
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).valueOrNull ?? '₦';

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Money', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
                  Row(
                    children: [
                      if (kDebugMode)
                        FulusIconButton(
                          icon: Icons.bug_report_outlined,
                          tooltip: 'Simulate error (debug)',
                          onPressed: _toggleSimulatedError,
                        ),
                      FulusIconButton(
                        icon: Icons.receipt_long_outlined,
                        tooltip: 'Money history',
                        onPressed: () => context.pushNamed('moneyHistory'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FutureBuilder<double>(
                future: _balanceFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionError(onRetry: _refresh, message: "Couldn't load your balance.");
                  }
                  if (!snapshot.hasData) {
                    return const FulusDelayedSkeleton(skeleton: _BalanceHeroSkeleton());
                  }
                  return _BalanceHero(balance: snapshot.data!, currencySymbol: currencySymbol);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const MoneyPeriodFilterBar(),
              const SizedBox(height: AppSpacing.lg),
              const _QuickActionsRow(),
              const SizedBox(height: AppSpacing.lg),
              FutureBuilder<MoneySummary>(
                future: _summaryFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionError(
                      onRetry: _refresh,
                      message: "Couldn't load this period's summary.",
                      reassurance: 'Your recorded sales, income, and expenses are safe — this is only about showing the totals right now.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const FulusDelayedSkeleton(skeleton: _SummarySkeleton());
                  }
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
              const SizedBox(height: AppSpacing.lg),
              FulusSectionHeader(
                title: 'Recent transactions',
                action: 'See all',
                onActionTap: () => context.pushNamed('moneyHistory'),
              ),
              FutureBuilder<List<MoneyTransaction>>(
                future: _recentFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _SectionError(onRetry: _refresh, message: "Couldn't load recent transactions.");
                  }
                  if (!snapshot.hasData) {
                    return const FulusDelayedSkeleton(
                      skeleton: Column(children: [
                        FulusListRowSkeleton(),
                        FulusListRowSkeleton(),
                        FulusListRowSkeleton(),
                      ]),
                    );
                  }
                  final items = snapshot.data!;
                  if (items.isEmpty) {
                    return const FulusEmptyState(
                      icon: Icons.receipt_long_outlined,
                      headline: 'Nothing recorded for this period.',
                      body: 'Sales, income, and expenses you record will show up here.',
                    );
                  }
                  return FulusCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const FulusListDivider(),
                          MoneyTransactionTile(
                            transaction: items[i],
                            currencySymbol: currencySymbol,
                            onTap: () => context.pushNamed(
                              'moneyTransactionDetail',
                              pathParameters: {'id': items[i].id},
                              extra: items[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.currencySymbol});
  final double balance;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppElevation.liftOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withOpacity(0.7)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatMoney(balance, symbol: currencySymbol),
            style: AppTypography.display.copyWith(
              color: AppColors.onPrimaryOf(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Net of every sale, expense, and payment recorded',
            style: AppTypography.body.copyWith(color: AppColors.onPrimaryOf(context).withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}

class _BalanceHeroSkeleton extends StatelessWidget {
  const _BalanceHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceAltOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusSkeletonBox(width: 130, height: 14),
          SizedBox(height: AppSpacing.md),
          FulusSkeletonBox(width: 210, height: 36),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.add,
            label: 'Add income',
            onTap: () => context.pushNamed('moneyAddIncome'),
          ),
        ),
        Expanded(
          child: _QuickAction(
            icon: Icons.remove,
            label: 'Add expense',
            onTap: () => context.pushNamed('moneyAddExpense'),
          ),
        ),
        Expanded(
          child: _QuickAction(
            icon: Icons.people_outline,
            label: 'Customers',
            onTap: () => context.pushNamed('moneyCustomers'),
          ),
        ),
        Expanded(
          child: _QuickAction(
            icon: Icons.local_shipping_outlined,
            label: 'Suppliers',
            onTap: () => context.pushNamed('moneySuppliers'),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppTouchTarget.minimum,
              height: AppTouchTarget.minimum,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.selectedTintOf(context)),
              child: Icon(icon, color: AppColors.primaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: AppColors.textPrimaryOf(context), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary, required this.currencySymbol, this.onBreakdownRowTap});

  final MoneySummary summary;
  final String currencySymbol;

  /// Volume 8: breakdown rows are "tappable through to the actual list
  /// of transactions behind it." Carries the tapped row into History
  /// via `extra` — see `money_history_screen.dart`.
  final ValueChanged<CategoryTotal>? onBreakdownRowTap;

  @override
  Widget build(BuildContext context) {
    final net = summary.net;
    final trendUp = net >= summary.previousNet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FulusStatCard(
                label: 'Money in',
                value: formatMoney(summary.moneyIn, symbol: currencySymbol),
                valueColor: AppColors.primaryOf(context),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FulusStatCard(
                label: 'Money out',
                value: formatMoney(summary.moneyOut, symbol: currencySymbol),
                valueColor: AppColors.errorOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        FulusStatCard(
          label: 'Net',
          value: formatMoney(net, symbol: currencySymbol, showSign: true),
          valueColor: net >= 0 ? AppColors.primaryOf(context) : AppColors.errorOf(context),
          trend: trendUp ? FulusTrend.up : FulusTrend.down,
          trendLabel: 'vs previous period',
        ),
        const SizedBox(height: AppSpacing.lg),
        MoneyBreakdownSection(
          title: 'Money in breakdown',
          rows: summary.incomeBreakdown,
          currencySymbol: currencySymbol,
          amountColor: AppColors.primaryOf(context),
          onRowTap: onBreakdownRowTap,
        ),
        MoneyBreakdownSection(
          title: 'Money out breakdown',
          rows: summary.expenseBreakdown,
          currencySymbol: currencySymbol,
          onRowTap: onBreakdownRowTap,
        ),
      ],
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(child: FulusStatCardSkeleton()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: FulusStatCardSkeleton()),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        FulusStatCardSkeleton(),
      ],
    );
  }
}

/// Inline section-level failure — "never a full-screen takeover unless
/// the entire screen's own data failed" (5.19); this screen has several
/// independently-loading sections, so each gets its own [FulusErrorState]
/// rather than one error replacing the whole page.
class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry, this.reassurance});
  final String message;
  final String? reassurance;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FulusErrorState(message: message, reassurance: reassurance, onRetry: onRetry);
  }
}
