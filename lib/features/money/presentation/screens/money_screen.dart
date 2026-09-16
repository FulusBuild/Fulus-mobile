import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart' show dataRefreshSignalProvider, sessionPermissionsProvider, sessionProvider;
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/ux/consumer_polish.dart';
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

/// Money workspace: balance, period summary, breakdowns, and recent activity.
/// All values remain repository-backed; this screen only controls presentation.
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
    final user = ref.read(sessionProvider);
    final currentAuthUserId = user?.id ?? '';
    final permissions = ref.read(sessionPermissionsProvider).value ?? const {};
    final canViewAllSales = user?.role == AuthRole.owner || permissions.contains(Permission.viewDashboardStats);
    _balanceFuture = repo.getAvailableBalance();
    _summaryFuture = repo.getSummary(period, currentAuthUserId: currentAuthUserId, canViewAllSales: canViewAllSales);
    _recentFuture = repo
        .getTransactions(period, currentAuthUserId: currentAuthUserId, canViewAllSales: canViewAllSales)
        .then((list) => list.take(5).toList());
  }

  Future<void> _refresh() async {
    setState(() => _load(_builtForPeriod ?? ref.read(moneyPeriodProvider)));
    await Future.wait([_balanceFuture, _summaryFuture, _recentFuture]);
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
          FulusIconButton(icon: Icons.bug_report_outlined, tooltip: 'Simulate error (debug)', onPressed: _toggleSimulatedError),
        FulusIconButton(icon: Icons.receipt_long_outlined, tooltip: 'Money history', onPressed: () => context.pushNamed('moneyHistory')),
        FulusIconButton(icon: Icons.receipt_outlined, tooltip: 'Receipts', onPressed: () => context.pushNamed('receiptHistory')),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final inset = fulusHorizontalInset(context);
          final wide = constraints.maxWidth >= 760;
          final contentWidth = wide ? 1120.0 : double.infinity;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
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
                    const SizedBox(height: AppSpacing.lg),
                    const _QuickActionsRow(),
                    const SizedBox(height: AppSpacing.lg),
                    FutureBuilder<MoneySummary>(
                      future: _summaryFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return _SectionError(onRetry: _refresh, message: "Couldn't load the money summary.");
                        if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: _SummarySkeleton());
                        return _SummaryContent(summary: snapshot.data!, currencySymbol: currencySymbol);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FutureBuilder<List<MoneyTransaction>>(
                      future: _recentFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return _SectionError(onRetry: _refresh, message: "Couldn't load recent transactions.");
                        if (!snapshot.hasData) return const FulusDelayedSkeleton(skeleton: _RecentSkeleton());
                        return _RecentTransactions(transactions: snapshot.data!, currencySymbol: currencySymbol);
                      },
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