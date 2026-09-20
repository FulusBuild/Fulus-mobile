import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_shell.dart';
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
      backgroundColor: AppColors.backgroundOf(context),
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
                        'Money',
                        style: AppTypography.heading.copyWith(
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Here’s what is happening with your money today.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondaryOf(context),
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
                      FulusSectionHeader(title: 'Money summary'),
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
    return Row(
      children: [
        FulusIconButton(
          icon: FulusIcons.menu,
          tooltip: 'Open navigation',
          onPressed: FulusAppShell.openDrawer,
        ),
        const SizedBox(width: AppSpacing.xs),
        const FulusBrandLogo(size: 32, padding: 7),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Fulus',
          style: AppTypography.subheading.copyWith(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
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
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.balance,
    required this.currencySymbol,
  });

  final double balance;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(balance, symbol: currencySymbol),
              style: AppTypography.display.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Net of every sale, income, expense, and payment recorded',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
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
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: FulusIcons.add,
        label: 'Add income',
        onTap: () => context.pushNamed('moneyAddIncome'),
      ),
      (
        icon: FulusIcons.remove,
        label: 'Add expense',
        onTap: () => context.pushNamed('moneyAddExpense'),
      ),
      (
        icon: FulusIcons.customers,
        label: 'Customers',
        onTap: () => context.pushNamed('moneyCustomers'),
      ),
      (
        icon: FulusIcons.localShipping,
        label: 'Suppliers',
        onTap: () => context.pushNamed('moneySuppliers'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: columns == 2 ? 1.7 : 1.25,
          ),
          itemBuilder: (context, index) => FulusQuickAction(
            icon: actions[index].icon,
            label: actions[index].label,
            onTap: actions[index].onTap,
          ),
        );
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;

        final moneyIn = Expanded(
          child: _MoneyStat(
            label: 'Money in',
            value: formatMoney(summary.moneyIn, symbol: currencySymbol),
            valueColor: AppColors.primaryOf(context),
          ),
        );
        final moneyOut = Expanded(
          child: _MoneyStat(
            label: 'Money out',
            value: formatMoney(summary.moneyOut, symbol: currencySymbol),
            valueColor: AppColors.errorOf(context),
          ),
        );

        return Column(
          children: [
            wide
                ? Row(
                    children: [
                      moneyIn,
                      const SizedBox(width: AppSpacing.md),
                      moneyOut,
                    ],
                  )
                : Column(
                    children: [
                      moneyIn,
                      const SizedBox(height: AppSpacing.sm),
                      moneyOut,
                    ],
                  ),
            const SizedBox(height: AppSpacing.sm),
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
          ],
        );
      },
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
    return FulusCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
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
        SizedBox(height: AppSpacing.sm),
        FulusStatCardSkeleton(),
      ],
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
