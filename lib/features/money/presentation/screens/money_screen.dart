import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider, sessionPermissionsProvider, sessionProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/mock_money_repository.dart';
import '../../domain/money_summary.dart';
import '../../domain/money_transaction.dart';
import '../providers/money_providers.dart';
import '../utils/money_format.dart';
import '../widgets/period_filter_bar.dart';
import '../widgets/transaction_tile.dart';

/// Money workspace: value first, then the actions and activity that explain it.
/// The layout follows the same simple hierarchy as Home while keeping all
/// existing repository-backed money flows intact.
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

  void _load(ReportPeriod period) {
    final repo = ref.read(moneyRepositoryProvider);
    _builtForPeriod = period;
    final user = ref.read(sessionProvider);
    final currentAuthUserId = user?.id ?? '';
    final permissions = ref.read(sessionPermissionsProvider).value ?? const <Permission>{};
    final canViewAllSales = user?.role == AuthRole.owner ||
        permissions.contains(Permission.viewDashboardStats);

    _balanceFuture = repo.getAvailableBalance();
    _summaryFuture = repo.getSummary(
      period,
      currentAuthUserId: currentAuthUserId,
      canViewAllSales: canViewAllSales,
    );
    _transactionsFuture = repo.getTransactions(
      period,
      currentAuthUserId: currentAuthUserId,
      canViewAllSales: canViewAllSales,
    );
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await Future.wait([_balanceFuture, _summaryFuture, _transactionsFuture]);
  }

  void _toggleSimulatedError() {
    final repo = ref.read(moneyRepositoryProvider);
    if (repo is MockMoneyRepository) {
      repo.debugSimulateFailure = !repo.debugSimulateFailure;
    }
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

    final currencySymbol =
        ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return Scaffold(
      backgroundColor: const Color(0xFF061B3A),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = fulusHorizontalInset(context);
              final maxWidth =
                  constraints.maxWidth >= 760 ? 1120.0 : double.infinity;

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      AppSpacing.md,
                      inset,
                      AppSpacing.xxxl,
                    ),
                    children: [
                      _MoneyHeader(
                        onHistory: () => context.pushNamed('moneyHistory'),
                        onReceipts: () => context.pushNamed('receiptHistory'),
                        onDebug: kDebugMode ? _toggleSimulatedError : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Here’s what is happening with your money today.',
                        style: AppTypography.body.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FutureBuilder<double>(
                        future: _balanceFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _MoneyError(
                              message: "Couldn't load your balance.",
                              onRetry: _refresh,
                            );
                          }
                          if (!snapshot.hasData) {
                            return const FulusDelayedSkeleton(
                              skeleton: _BalanceHeroSkeleton(),
                            );
                          }
                          return _BalanceHero(
                            balance: snapshot.data!,
                            currencySymbol: currencySymbol,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _MoneyQuickActions(),
                      const SizedBox(height: AppSpacing.xl),
                      const MoneyPeriodFilterBar(),
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Money summary',
                        action: 'See all',
                        onActionTap: () => context.pushNamed('moneyHistory'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FutureBuilder<MoneySummary>(
                        future: _summaryFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _MoneyError(
                              message: "Couldn't load this period's summary.",
                              onRetry: _refresh,
                            );
                          }
                          if (!snapshot.hasData) {
                            return const FulusDelayedSkeleton(
                              skeleton: _SummarySkeleton(),
                            );
                          }
                          return _MoneySummary(
                            summary: snapshot.data!,
                            currencySymbol: currencySymbol,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => context.pushNamed('moneyCustomers'),
                              icon: const Icon(FulusIcons.customers),
                              label: const Text('Customer credit'),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => context.pushNamed('moneySuppliers'),
                              icon: const Icon(FulusIcons.localShipping),
                              label: const Text('Suppliers'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Recent activity',
                        action: 'See all',
                        onActionTap: () =>
                            context.pushNamed('moneyHistory'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FutureBuilder<List<MoneyTransaction>>(
                        future: _transactionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _MoneyError(
                              message: "Couldn't load recent activity.",
                              onRetry: _refresh,
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Column(
                              children: [
                                FulusListRowSkeleton(),
                                FulusListRowSkeleton(),
                                FulusListRowSkeleton(),
                              ],
                            );
                          }

                          final transactions =
                              snapshot.data!.take(5).toList();
                          if (transactions.isEmpty) {
                            return const FulusEmptyState(
                              icon: FulusIcons.receipt,
                              headline: 'No activity yet',
                              body:
                                  'Sales, income, expenses, and payments you record will show up here.',
                            );
                          }

                          return FulusCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i < transactions.length;
                                    i++) ...[
                                  if (i > 0) const FulusListDivider(),
                                  MoneyTransactionTile(
                                    transaction: transactions[i],
                                    currencySymbol: currencySymbol,
                                    showDate: false,
                                    onTap: () => context.pushNamed(
                                      'moneyTransactionDetail',
                                      pathParameters: {
                                        'id': transactions[i].id,
                                      },
                                      extra: transactions[i],
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MoneyHeader extends StatelessWidget {
  const _MoneyHeader({
    required this.onHistory,
    required this.onReceipts,
    required this.onDebug,
  });

  final VoidCallback onHistory;
  final VoidCallback onReceipts;
  final VoidCallback? onDebug;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onDebug != null)
        FulusIconButton(
          icon: FulusIcons.bugReport,
          tooltip: 'Simulate error (debug)',
          onPressed: onDebug,
        ),
      FulusIconButton(
        icon: FulusIcons.history,
        tooltip: 'Money history',
        onPressed: onHistory,
      ),
      FulusIconButton(
        icon: FulusIcons.receipt,
        tooltip: 'Receipts',
        onPressed: onReceipts,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.15;
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Money',
                    style: AppTypography.subheading.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: actions,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    'Money',
                    style: AppTypography.subheading.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  ...actions,
                ],
              );
      },
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.currencySymbol});
  final double balance;
  final String currencySymbol;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 142),
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(color: const Color(0xFF0BBE6E), borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(FulusIcons.money, color: Colors.white, size: 28), SizedBox(width: AppSpacing.sm), Text('Available Balance', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))]),
      const Spacer(),
      FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(formatMoney(balance, symbol: currencySymbol), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900))),
      const Text('Updated from your business records', style: TextStyle(color: Colors.white70, fontSize: 12)),
    ]),
  );
}
class _BalanceHeroSkeleton extends StatelessWidget {
  const _BalanceHeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FulusSkeletonBox(width: 130, height: 14),
          SizedBox(height: AppSpacing.md),
          FulusSkeletonBox(width: 210, height: 36),
        ],
      ),
    );
  }
}

class _MoneyQuickActions extends StatelessWidget {
  const _MoneyQuickActions();
  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, String subtitle, Color color, VoidCallback onTap})>[
      (icon: FulusIcons.add, label: 'Money In', subtitle: 'Record income', color: const Color(0xFF0BBE6E), onTap: () => context.pushNamed('moneyAddIncome')),
      (icon: FulusIcons.remove, label: 'Money Out', subtitle: 'Record expense', color: const Color(0xFF7B3FF2), onTap: () => context.pushNamed('moneyAddExpense')),
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: AppSpacing.sm, mainAxisSpacing: AppSpacing.sm, mainAxisExtent: 106),
      itemBuilder: (context, index) {
        final a=actions[index];
        return Material(color:a.color, borderRadius:BorderRadius.circular(12), child:InkWell(onTap:a.onTap,borderRadius:BorderRadius.circular(12),child:Padding(padding:const EdgeInsets.all(AppSpacing.md),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(a.icon,color:Colors.white,size:25),const Spacer(),Text(a.label,style:const TextStyle(color:Colors.white,fontSize:13,fontWeight:FontWeight.w800)),Text(a.subtitle,style:const TextStyle(color:Colors.white70,fontSize:10))]))));
      },
    );
  }
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({
    required this.summary,
    required this.currencySymbol,
  });

  final MoneySummary summary;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final net = summary.net;
    final netUp = net >= summary.previousNet;

    return FulusCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;

          final stats = [
            _MoneyStat(
              label: 'Money in',
              value: formatMoney(
                summary.moneyIn,
                symbol: currencySymbol,
              ),
              valueColor: AppColors.primaryOf(context),
            ),
            _MoneyStat(
              label: 'Money out',
              value: formatMoney(
                summary.moneyOut,
                symbol: currencySymbol,
              ),
              valueColor: AppColors.errorOf(context),
            ),
            _MoneyStat(
              label: 'Net',
              value: formatMoney(
                net,
                symbol: currencySymbol,
                showSign: true,
              ),
              valueColor: net >= 0
                  ? AppColors.primaryOf(context)
                  : AppColors.errorOf(context),
              trend: netUp ? 'vs previous period' : 'below previous period',
            ),
          ];

          // The summary lives inside a vertical ListView, so its row
          // must provide its own minimum cross-axis height. Without an
          // explicit height/intrinsic constraint, three Expanded children
          // can resolve to a zero-height row on some Flutter layouts,
          // leaving "Money summary" followed by a completely blank area
          // until another navigation rebuild happens.
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    color: AppColors.borderOf(context),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact
                          ? AppSpacing.xs
                          : AppSpacing.sm,
                    ),
                    child: stats[i],
                  ),
                ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({
    required this.label,
    required this.value,
    required this.valueColor,
    this.trend,
  });

  final String label;
  final String value;
  final Color valueColor;
  final String? trend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppTypography.subheading.copyWith(
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (trend != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            trend!,
            maxLines: 2,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: FulusStatCardSkeleton()),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          ),
          const Expanded(child: FulusStatCardSkeleton()),
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          ),
          const Expanded(child: FulusStatCardSkeleton()),
        ],
      ),
    );
  }
}

class _MoneyError extends StatelessWidget {
  const _MoneyError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FulusErrorState(
      message: message,
      reassurance:
          'Your recorded money data is still safe on this device.',
      onRetry: onRetry,
    );
  }
}
