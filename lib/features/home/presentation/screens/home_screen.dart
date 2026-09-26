import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  });

  final String currentAuthUserId;
  final bool isOwner;
  final bool canViewDashboardStats;

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
      backgroundColor: AppColors.backgroundOf(context),
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
                        businessName:
                            ref.watch(_businessProfileProvider).value?.businessName.trim() ??
                                '',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        '${greetingForHour(DateTime.now().hour)}, ${_displayName(ref)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        showBusinessWide ? 'Here’s what is happening in your business today.' : 'Here’s what is happening on your shift today.',
                        style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FutureBuilder<HomeHeroState>(
                        future: _heroFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) return const _HomeHeroSkeleton();
                          if (snapshot.hasError) {
                            return FulusErrorState(
                              message: "Couldn't load today's sales.",
                              reassurance: 'Your sales are still safe on this device.',
                              onRetry: _refresh,
                            );
                          }
                          if (!snapshot.hasData) {
                            return const FulusEmptyState(
                              headline: 'Nothing to show yet',
                              body: 'Your sales summary will appear here when there is data to show.',
                              icon: FulusIcons.stock,
                            );
                          }
                          return _HomeSalesCard(state: snapshot.data!, currencySymbol: currencySymbol);
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _HomeQuickActions(),
                      if (showBusinessWide) ...[
                        const SizedBox(height: AppSpacing.xl),
                        FutureBuilder<SecondaryNoticeSelection>(
                          future: _noticesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState != ConnectionState.done) return const _NoticeSkeleton();
                            if (snapshot.hasError) {
                              return FulusErrorState(
                                message: "Couldn't load business alerts.",
                                reassurance: 'Your business data is still safe on this device.',
                                onRetry: _refresh,
                              );
                            }
                            final selection = snapshot.data;
                            if (selection == null || selection.shown.isEmpty) return const SizedBox.shrink();
                            return _AttentionSection(selection: selection, currencySymbol: currencySymbol);
                          },
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Recent activity',
                        action: 'See all',
                        onActionTap: () => context.pushNamed('moneyHistory'),
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
                                    onTap: () => context.pushNamed(
                                      'moneyTransactionDetail',
                                      pathParameters: {'id': transactions[i].id},
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

  String _displayName(WidgetRef ref) {
    final profile = ref.watch(_businessProfileProvider).value;
    final user = ref.watch(sessionProvider);
    final isOwner = user == null || user.role == AuthRole.owner;
    if (isOwner) return profile?.businessName.trim().isNotEmpty == true ? profile!.businessName.trim() : 'there';
    return user.fullName.trim().isNotEmpty == true ? user.fullName.trim() : 'there';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.businessName});

  final String businessName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            businessName.isEmpty ? 'Business' : businessName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.subheading.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        const FulusSyncStatusIndicator(),
      ],
    );
  }
}

class _HomeSalesCard extends StatelessWidget {
  const _HomeSalesCard({required this.state, required this.currencySymbol});
  final HomeHeroState state;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final (label, amount, count) = switch (state) {
      NotYetOpenedHero(:final yesterdayTotal, :final yesterdaySalesCount) => ('Yesterday', yesterdayTotal, yesterdaySalesCount),
      OpenHero(:final todayTotal, :final todaySalesCount) => ('Today’s sales', todayTotal, todaySalesCount),
      ClosedHero(:final finalTotal, :final finalSalesCount) => ('Today’s sales · Closed', finalTotal, finalSalesCount),
      EmployeeShiftHero(:final shiftTotal, :final shiftSalesCount) => ('Your shift', shiftTotal, shiftSalesCount),
    };

    String? trend;
    if (state case OpenHero(:final todayTotal, :final yesterdayTotal) when yesterdayTotal > 0) {
      final delta = ((todayTotal - yesterdayTotal) / yesterdayTotal) * 100;
      trend = '${delta >= 0 ? '+' : ''}${delta.round()}% vs yesterday';
    }

    return FulusCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600))),
              if (trend != null)
                Text(trend, style: AppTypography.caption.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(formatMoney(amount, symbol: currencySymbol), style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context), fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('$count sale${count == 1 ? '' : 's'} today', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
          ],
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (icon: FulusIcons.sell, label: 'Sell', onTap: () => context.goNamed('sell')),
      (icon: FulusIcons.stock, label: 'Stock', onTap: () => context.goNamed('stock')),
      (icon: FulusIcons.money, label: 'Money', onTap: () => context.goNamed('money')),
      (icon: FulusIcons.reports, label: 'Reports', onTap: () => context.pushNamed('moreReports')),
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
            childAspectRatio: columns == 2 ? 2.0 : 1.35,
          ),
          itemBuilder: (context, index) => FulusQuickAction(icon: actions[index].icon, label: actions[index].label, onTap: actions[index].onTap),
        );
      },
    );
  }
}

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({required this.selection, required this.currencySymbol});
  final SecondaryNoticeSelection selection;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final shown = selection.shown.where((notice) => notice.type != SecondaryNoticeType.unsyncedItems).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FulusSectionHeader(title: 'Needs attention'),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shown.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final notice = shown[index];
              switch (notice.type) {
                case SecondaryNoticeType.lowStock:
                  return _AttentionCard(label: notice.label, value: notice.value.toInt().toString(), icon: FulusIcons.stock, onTap: () => context.goNamed('stock'));
                case SecondaryNoticeType.pendingCredit:
                  return _AttentionCard(label: notice.label, value: formatMoney(notice.value.toDouble(), symbol: currencySymbol, compact: true), icon: FulusIcons.payments, onTap: () => context.pushNamed('moneyCustomers'));
                case SecondaryNoticeType.unsyncedItems:
                  // Filtered above; keep the switch exhaustive for the enum.
                  return const SizedBox.shrink();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 176,
      child: FulusCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryOf(context)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w800)),
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroSkeleton extends StatelessWidget {
  const _HomeHeroSkeleton();
  @override
  Widget build(BuildContext context) => const FulusSkeletonBox(height: 170);
}

class _NoticeSkeleton extends StatelessWidget {
  const _NoticeSkeleton();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 92, child: Row(children: [Expanded(child: FulusSkeletonBox()), SizedBox(width: AppSpacing.sm), Expanded(child: FulusSkeletonBox())]));
}

final _businessProfileProvider = StreamProvider.autoDispose<BusinessProfile?>((ref) => ref.watch(businessSettingsRepositoryProvider).watchSettings());
