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
                      const SizedBox(height: AppSpacing.xl),
                      FulusSectionHeader(
                        title: 'Recent activity',
                        action: (widget.isOwner || widget.canViewMoney) ? 'See all' : null,
                        onActionTap: (widget.isOwner || widget.canViewMoney) ? () => context.pushNamed('moneyHistory') : null,
                      ),
                      FutureBuilder<List<MoneyTransaction>>(
                        future: _activityFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) return const Column(children: [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()]);
                          if (snapshot.hasError) return FulusErrorState(message: "Couldn't load recent activity.", reassurance: 'Your sales and money records are still safe on this device.', onRetry: _refresh);
                          final transactions = snapshot.data ?? const <MoneyTransaction>[];
                          if (transactions.isEmpty) return const FulusEmptyState(headline: 'No activity yet today', body: 'Sales, stock, and expenses you record will show up here.', icon: FulusIcons.receipt);
                          return FulusCard(padding: EdgeInsets.zero, child: Column(children: [for (var i = 0; i < transactions.length.clamp(0, 5); i++) ...[if (i > 0) const FulusListDivider(), MoneyTransactionTile(transaction: transactions[i], currencySymbol: currencySymbol, showDate: false, onTap: (widget.isOwner || widget.canViewMoney) ? () => context.pushNamed('moneyTransactionDetail', pathParameters: {'id': transactions[i].id}, extra: transactions[i]) : null)]]));
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


class _HomeMockupDashboard extends StatelessWidget {
  const _HomeMockupDashboard({
    required this.hero,
    required this.notices,
    required this.activity,
    required this.currencySymbol,
  });
  final HomeHeroState hero;
  final List<SecondaryNotice> notices;
  final List<MoneyTransaction> activity;
  final String currencySymbol;

  double get _salesTotal => switch (hero) {
    NotYetOpenedHero(:final yesterdayTotal) => yesterdayTotal,
    OpenHero(:final todayTotal) => todayTotal,
    ClosedHero(:final finalTotal) => finalTotal,
    EmployeeShiftHero(:final shiftTotal) => shiftTotal,
  };
  int get _salesCount => switch (hero) {
    NotYetOpenedHero(:final yesterdaySalesCount) => yesterdaySalesCount,
    OpenHero(:final todaySalesCount) => todaySalesCount,
    ClosedHero(:final finalSalesCount) => finalSalesCount,
    EmployeeShiftHero(:final shiftSalesCount) => shiftSalesCount,
  };
  double get _cashTotal => activity.fold<double>(0, (sum, tx) => sum + tx.signedAmount);
  double get _expensesTotal => activity.where((tx) => tx.type == MoneyTransactionType.expense).fold<double>(0, (sum, tx) => sum + tx.amount);
  int get _lowStockCount => notices.where((n) => n.type == SecondaryNoticeType.lowStock).fold<int>(0, (sum, n) => sum + n.value.toInt());
  double get _creditTotal => notices.where((n) => n.type == SecondaryNoticeType.pendingCredit).fold<double>(0, (sum, n) => sum + n.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final recent = activity.take(2).toList(growable: false);
    return Column(
      children: [
        _HomeHeroCard(icon: FulusIcons.money, label: 'Total Cash', value: formatMoney(_cashTotal, symbol: currencySymbol, compact: true), secondary: 'Business cash position'),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.green, icon: FulusIcons.sell, label: 'Today’s Sales', value: formatMoney(_salesTotal, symbol: currencySymbol, compact: true), secondary: '${_salesCount} sales')),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.orange, icon: FulusIcons.stock, label: 'Low Stock', value: '${_lowStockCount}', secondary: 'items')),
        ]),
        const SizedBox(height: AppSpacing.sm),
        _HomeSummaryCard(credit: formatMoney(_creditTotal, symbol: currencySymbol, compact: true), expenses: formatMoney(_expensesTotal, symbol: currencySymbol, compact: true), recent: recent),
      ],
    );
  }
}

class _HomeHeroCard extends StatelessWidget {
  const _HomeHeroCard({required this.icon, required this.label, required this.value, required this.secondary});
  final IconData icon; final String label; final String value; final String secondary;
  @override
  Widget build(BuildContext context) => Material(
    color: _HomeColors.blue, borderRadius: BorderRadius.circular(AppRadius.md),
    child: SizedBox(height: 112, child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: Colors.white, size: AppIconSize.base), const SizedBox(width: AppSpacing.sm), Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))]),
        const Spacer(),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))),
        Text(secondary, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    )),
  );
}

class _HomeCompactCard extends StatelessWidget {
  const _HomeCompactCard({required this.color, required this.icon, required this.label, required this.value, required this.secondary});
  final Color color; final IconData icon; final String label; final String value; final String secondary;
  @override
  Widget build(BuildContext context) => Material(
    color: color, borderRadius: BorderRadius.circular(AppRadius.md),
    child: SizedBox(height: 86, child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.white, size: AppIconSize.compact),
        const Spacer(),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
        Text(secondary, style: const TextStyle(color: Colors.white70, fontSize: 9)),
      ]),
    )),
  );
}

class _HomeSummaryCard extends StatelessWidget {
  const _HomeSummaryCard({required this.credit, required this.expenses, required this.recent});
  final String credit; final String expenses; final List<MoneyTransaction> recent;
  @override
  Widget build(BuildContext context) => FulusCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Business snapshot', style: AppTypography.label.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w800)),
      const SizedBox(height: AppSpacing.sm),
      Text('Customer credit  $credit', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      Text('Expenses today  $expenses', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      if (recent.isNotEmpty) Text('Recent: ${recent.first.description}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      const SizedBox(height: AppSpacing.sm),
      Row(children: [
        Expanded(child: _QuickActionButton(icon: FulusIcons.sell, label: 'Sell', color: _HomeColors.blue, onTap: () => context.goNamed('sell'))),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: _QuickActionButton(icon: FulusIcons.stock, label: 'Stock', color: _HomeColors.orange, onTap: () => context.goNamed('stock'))),
      ]),
    ]),
  );
}

class _HomeSalesCard extends StatelessWidget {
  const _HomeSalesCard({required this.state, required this.currencySymbol});
  final HomeHeroState state;
  final String currencySymbol;
  @override
  Widget build(BuildContext context) {
    final (label, amount, count, countLabel) = switch (state) {
      NotYetOpenedHero(:final yesterdayTotal, :final yesterdaySalesCount) => ('Yesterday', yesterdayTotal, yesterdaySalesCount, 'sales yesterday'),
      OpenHero(:final todayTotal, :final todaySalesCount) => ('Today’s sales', todayTotal, todaySalesCount, 'sales today'),
      ClosedHero(:final finalTotal, :final finalSalesCount) => ('Today’s sales · Closed', finalTotal, finalSalesCount, 'sales today'),
      EmployeeShiftHero(:final shiftTotal, :final shiftSalesCount) => ('Your shift', shiftTotal, shiftSalesCount, 'sales in your shift'),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: _HomeColors.green, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(FulusIcons.sell, color: Colors.white, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        const Spacer(),
        FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(formatMoney(amount, symbol: currencySymbol), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900))),
        Text(count.toString() + ' ' + countLabel.replaceFirst('sales', count == 1 ? 'sale' : 'sales'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }
}
class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.canViewMoney, required this.canViewReports});
  final bool canViewMoney;
  final bool canViewReports;
  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, String subtitle, Color color, VoidCallback onTap})>[
      (icon: FulusIcons.sell, label: 'Sell', subtitle: 'Start a sale', color: _HomeColors.blue, onTap: () => context.goNamed('sell')),
      (icon: FulusIcons.stock, label: 'Stock', subtitle: 'Manage inventory', color: _HomeColors.orange, onTap: () => context.goNamed('stock')),
      if (canViewMoney) (icon: FulusIcons.money, label: 'Money', subtitle: 'Track your money', color: _HomeColors.green, onTap: () => context.goNamed('money')),
      if (canViewReports) (icon: FulusIcons.reports, label: 'Reports', subtitle: 'See business trends', color: _HomeColors.purple, onTap: () => context.pushNamed('moreReports')),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 4 : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: AppSpacing.sm, mainAxisSpacing: AppSpacing.sm, mainAxisExtent: 112),
        itemBuilder: (context, index) {
          final a = actions[index];
          return _HomeActionCard(icon: a.icon, label: a.label, subtitle: a.subtitle, color: a.color, onTap: a.onTap);
        },
      );
    });
  }
}
class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({required this.icon, required this.label, required this.subtitle, required this.color, required this.onTap});
  final IconData icon; final String label; final String subtitle; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.white, size: 28),
          const Spacer(),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      ),
    ),
  );
}
class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.selection,
    required this.currencySymbol,
    required this.canViewMoney,
  });

  final SecondaryNoticeSelection selection;
  final String currencySymbol;
  final bool canViewMoney;

  @override
  Widget build(BuildContext context) {
    final shown = selection.shown.where((notice) {
      if (notice.type == SecondaryNoticeType.unsyncedItems) return false;
      if (notice.type == SecondaryNoticeType.pendingCredit && !canViewMoney) return false;
      return true;
    }).toList();
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
  const _AttentionCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 192,
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: '$value $label',
        child: FulusCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.selectedTintOf(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: AppIconSize.compact, color: AppColors.primaryOf(context)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subheading.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            ],
          ),
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
