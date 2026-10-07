import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fulus_mobile/core/money/money.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider, sessionPermissionsProvider, sessionProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/async_timeout.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/report.dart';
import '../../../../shared/widgets/widgets.dart';
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
  late Future<Money> _balanceFuture;
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

    _balanceFuture = repo.getAvailableBalance().withFulusLoadingTimeout();
    // Keep the first useful frame independent: recent activity can hydrate
    // as soon as its transaction read completes, without waiting for the
    // summary aggregation. Both reads start together and preserve the same
    // permission/location scoping.
    _summaryFuture = repo.getSummary(
      period,
      currentAuthUserId: currentAuthUserId,
      canViewAllSales: canViewAllSales,
    ).withFulusLoadingTimeout();
    _transactionsFuture = repo.getTransactions(
      period,
      currentAuthUserId: currentAuthUserId,
      canViewAllSales: canViewAllSales,
    ).withFulusLoadingTimeout();
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await Future.wait([_balanceFuture, _summaryFuture, _transactionsFuture]);
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

    return FulusScreen(
      title: 'Money',
      actions: [
        FulusIconButton(icon: FulusIcons.history, tooltip: 'Money history', onPressed: () => context.pushNamed('moneyHistory')),
      ],
      applyPadding: false,
      body: DefaultTextStyle.merge(
        style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
        child: SafeArea(
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
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      AppSpacing.md,
                      inset,
                      AppSpacing.xxxl,
                    ),
                    children: [
                      FutureBuilder<Money>(
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
                      FutureBuilder<MoneySummary>(
                        future: _summaryFuture,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _MoneyError(
                              message: "Couldn't load this period's money data.",
                              onRetry: _refresh,
                            );
                          }
                          if (!snapshot.hasData) {
                            return const FulusDelayedSkeleton(
                              skeleton: FulusSkeletonBox(height: 118),
                            );
                          }
                          return _MoneyQuickActions(
                            summary: snapshot.data!,
                            currencySymbol: currencySymbol,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      const MoneyPeriodFilterBar(),
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Recent activity',
                        titleColor: AppColors.textPrimaryOf(context),
                        subtitleColor: AppColors.textSecondaryOf(context),
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

                          final transactions = snapshot.data!.take(5).toList();
                          if (transactions.isEmpty) {
                            return const FulusEmptyState(
                              icon: FulusIcons.receipt,
                              headline: 'No activity yet',
                              body:
                                  'Sales, income, expenses, and payments you record will show up here.',
                            );
                          }

                          return Column(
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
      ),
    );
  }
}


class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.currencySymbol});
  final Money balance;
  final String currencySymbol;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 142,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(AppRadius.xl)),
      child: Builder(builder: (context) {
        final foreground = AppColors.onColor(AppColors.success);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(FulusIcons.wallet, color: foreground, size: 40), const SizedBox(width: AppSpacing.sm), Text('Available Balance', style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w700))]),
        const SizedBox(height: AppSpacing.sm),
        FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(formatMoney(balance, symbol: currencySymbol), style: TextStyle(color: foreground, fontSize: 28, fontWeight: FontWeight.w800))),
        const SizedBox(height: AppSpacing.xs),
  
      ]);
      }),
    ),
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
  const _MoneyQuickActions({
    required this.summary,
    required this.currencySymbol,
  });

  final MoneySummary summary;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final actions = <_MoneyAction>[
      _MoneyAction(
        color: AppColors.success,
        icon: FulusIcons.moneyIn,
        label: 'Money In',
        value: formatMoney(summary.moneyIn, symbol: currencySymbol),
        onTap: () => context.pushNamed('moneyAddIncome'),
      ),
      _MoneyAction(
        color: AppColors.warning,
        icon: FulusIcons.moneyOut,
        label: 'Money Out',
        value: formatMoney(summary.moneyOut, symbol: currencySymbol),
        onTap: () => context.pushNamed('moneyAddExpense'),
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: _MoneyActionCell(action: actions[i])),
        ],
      ],
    );
  }
}

class _MoneyActionCell extends StatelessWidget {
  const _MoneyActionCell({required this.action});
  final _MoneyAction action;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.xl);
    return Material(
      color: action.color.withValues(alpha: 0.10),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: action.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(action.icon, size: AppIconSize.emphasis, color: action.color),
              const Spacer(),
              Text(action.label, style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(action.value, style: AppTypography.heading.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyAction {
  const _MoneyAction({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
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
