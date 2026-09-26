import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_shell.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/dashboard_summary.dart';
import '../../../../domain/entities/report.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/domain/money_transaction.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider, moneyRepositoryProvider;
import '../../../money/presentation/widgets/transaction_tile.dart';

/// Owner/manager workspace home. Data and permissions remain repository-backed;
/// this screen only changes the presentation hierarchy to match the reference UI.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.currentAuthUserId,
    required this.isOwner,
    required this.canViewDashboardStats,
    required this.canViewMoney,
    required this.canViewReports,
  });

  final String currentAuthUserId;
  final bool isOwner;
  final bool canViewDashboardStats;
  final bool canViewMoney;
  final bool canViewReports;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<HomeHeroState> _heroFuture;
  late Future<SecondaryNoticeSelection> _noticesFuture;
  late Future<List<MoneyTransaction>> _activityFuture;
  static const _reportsEngine = ReportsEngine();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(dashboardRepositoryProvider);
    final showBusinessWide = widget.isOwner || widget.canViewDashboardStats;
    final locationFuture = ref.read(activeLocationIdProvider.future);
    _heroFuture = locationFuture.then((locationId) => repo.getHeroState(
          currentAuthUserId: widget.currentAuthUserId,
          isOwner: showBusinessWide,
          locationId: locationId,
        ));
    _noticesFuture = locationFuture.then((locationId) => repo.getSecondaryNotices(
          locationId: locationId,
          max: 3,
        ));
    _activityFuture = ref.read(moneyRepositoryProvider).getTransactions(
          _reportsEngine.resolvePeriod(ReportPeriodKind.today),
          currentAuthUserId: widget.currentAuthUserId,
          canViewAllSales: showBusinessWide,
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture, _activityFuture]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) setState(_load);
    });

    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final showBusinessWide = widget.isOwner || widget.canViewDashboardStats;

    return Scaffold(
      backgroundColor: _HomeColors.navy,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = fulusHorizontalInset(context);
              final maxWidth = constraints.maxWidth >= 760 ? 1120.0 : double.infinity;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.xxxl),
                    children: [
                      _HomeHeader(
                        businessName: ref.watch(_businessProfileProvider).value?.businessName.trim() ?? '',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '${greetingForHour(DateTime.now().hour)}, ${_displayName(ref)} 👋',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTypography.heading.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        showBusinessWide ? 'Here’s what’s happening with your business today.' : 'Here’s what’s happening on your shift today.',
                        style: AppTypography.caption.copyWith(color: _HomeColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FutureBuilder<HomeHeroState>(
                        future: _heroFuture,
                        builder: (context, heroSnapshot) => FutureBuilder<SecondaryNoticeSelection>(
                          future: _noticesFuture,
                          builder: (context, noticeSnapshot) => FutureBuilder<List<MoneyTransaction>>(
                            future: _activityFuture,
                            builder: (context, activitySnapshot) {
                              if (heroSnapshot.connectionState != ConnectionState.done || noticeSnapshot.connectionState != ConnectionState.done || activitySnapshot.connectionState != ConnectionState.done) return const _HomeHeroSkeleton();
                              if (heroSnapshot.hasError || noticeSnapshot.hasError || activitySnapshot.hasError) return FulusErrorState(message: "Couldn't load today's overview.", reassurance: 'Your business records are still safe on this device.', onRetry: _refresh);
                              final hero = heroSnapshot.data;
                              if (hero == null) return const SizedBox.shrink();
                              return _HomeMockupDashboard(hero: hero, notices: noticeSnapshot.data?.shown ?? const <SecondaryNotice>[], activity: activitySnapshot.data ?? const <MoneyTransaction>[], currencySymbol: currencySymbol);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Recent activity',
                        action: (widget.isOwner || widget.canViewMoney) ? 'See all' : null,
                        onActionTap: (widget.isOwner || widget.canViewMoney) ? () => context.pushNamed('moneyHistory') : null,
                      ),
                      FutureBuilder<List<MoneyTransaction>>(
                        future: _activityFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]);
                          }
                          if (snapshot.hasError) {
                            return FulusErrorState(
                              message: "Couldn't load recent activity.",
                              reassurance: 'Your sales and money records are still safe on this device.',
                              onRetry: _refresh,
                            );
                          }
                          final transactions = snapshot.data ?? const <MoneyTransaction>[];
                          if (transactions.isEmpty) {
                            return const FulusEmptyState(
                              headline: 'No activity yet today',
                              body: 'Sales, stock, and expenses you record will show up here.',
                              icon: FulusIcons.receipt,
                            );
                          }
                          return FulusCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < transactions.length.clamp(0, 5); i++) ...[
                                  if (i > 0) const FulusListDivider(),
                                  MoneyTransactionTile(
                                    transaction: transactions[i],
                                    currencySymbol: currencySymbol,
                                    showDate: false,
                                    onTap: (widget.isOwner || widget.canViewMoney)
                                        ? () => context.pushNamed(
                                            'moneyTransactionDetail',
                                            pathParameters: {'id': transactions[i].id},
                                            extra: transactions[i],
                                          )
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),