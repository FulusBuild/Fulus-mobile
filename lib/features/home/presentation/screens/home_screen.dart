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
  late Future<double> _cashFuture;
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
    _cashFuture = (widget.isOwner || widget.canViewMoney)
        ? ref.read(moneyRepositoryProvider).getAvailableBalance()
        : Future.value(0);
    _activityFuture = ref.read(moneyRepositoryProvider).getTransactions(
          _reportsEngine.resolvePeriod(ReportPeriodKind.today),
          currentAuthUserId: widget.currentAuthUserId,
          canViewAllSales: showBusinessWide,
        );
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture, _activityFuture, _cashFuture]);
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
        child: LayoutBuilder(
          builder: (context, constraints) {
              final inset = fulusHorizontalInset(context);
              final maxWidth = constraints.maxWidth >= 760 ? 1120.0 : double.infinity;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: CustomScrollView(
                    // Home is a dashboard, not a feed. The normal dashboard must
                    // stay locked to the viewport rather than becoming vertically
                    // scrollable just to reveal the six cards.
                    physics: const NeverScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.lg),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HomeHeader(
                                businessName: ref.watch(_businessProfileProvider).value?.businessName.trim() ?? '',
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                '${greetingForHour(DateTime.now().hour)}, ${_displayName(ref)} 👋',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.heading.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                showBusinessWide
                                    ? 'Here’s what’s happening with your business today.'
                                    : 'Here’s what’s happening on your shift today.',
                                style: AppTypography.caption.copyWith(color: _HomeColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(inset, 0, inset, inset * 1.75),
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: FutureBuilder<HomeHeroState>(
                            future: _heroFuture,
                            builder: (context, heroSnapshot) => FutureBuilder<SecondaryNoticeSelection>(
                              future: _noticesFuture,
                              builder: (context, noticeSnapshot) => FutureBuilder<List<MoneyTransaction>>(
                                future: _activityFuture,
                                builder: (context, activitySnapshot) => FutureBuilder<double>(
                                  future: _cashFuture,
                                  builder: (context, cashSnapshot) {
                                    if (heroSnapshot.connectionState != ConnectionState.done ||
                                        noticeSnapshot.connectionState != ConnectionState.done ||
                                        activitySnapshot.connectionState != ConnectionState.done ||
                                        cashSnapshot.connectionState != ConnectionState.done) {
                                      return const _HomeHeroSkeleton();
                                    }
                                    if (heroSnapshot.hasError ||
                                        noticeSnapshot.hasError ||
                                        activitySnapshot.hasError ||
                                        cashSnapshot.hasError) {
                                      return FulusErrorState(
                                        message: "Couldn't load today's overview.",
                                        reassurance: 'Your business records are still safe on this device.',
                                        onRetry: _refresh,
                                      );
                                    }
                                    final hero = heroSnapshot.data;
                                    if (hero == null || cashSnapshot.data == null) return const SizedBox.shrink();
                                    return _HomeMockupDashboard(
                                      hero: hero,
                                      notices: noticeSnapshot.data?.shown ?? const <SecondaryNotice>[],
                                      activity: activitySnapshot.data ?? const <MoneyTransaction>[],
                                      cashTotal: cashSnapshot.data!,
                                      currencySymbol: currencySymbol,
                                      canViewMoney: widget.isOwner || widget.canViewMoney,
                                      canViewReports: widget.isOwner || widget.canViewReports,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
        const FulusBrandLogo(
          size: 56,
          padding: 2,
          showBackground: false,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            businessName.isEmpty ? 'Fulus' : businessName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeMockupDashboard extends StatelessWidget {
  const _HomeMockupDashboard({
    required this.hero,
    required this.notices,
    required this.activity,
    required this.cashTotal,
    required this.currencySymbol,
    required this.canViewMoney,
    required this.canViewReports,
  });
  final HomeHeroState hero;
  final List<SecondaryNotice> notices;
  final List<MoneyTransaction> activity;
  final double? cashTotal;
  final String currencySymbol;
  final bool canViewMoney;
  final bool canViewReports;

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
  double get _expensesTotal => activity.where((tx) => tx.type == MoneyTransactionType.expense).fold<double>(0, (sum, tx) => sum + tx.amount);
  int get _lowStockCount => notices.where((n) => n.type == SecondaryNoticeType.lowStock).fold<int>(0, (sum, n) => sum + n.value.toInt());
  double get _creditTotal => notices.where((n) => n.type == SecondaryNoticeType.pendingCredit).fold<double>(0, (sum, n) => sum + n.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.blue, icon: FulusIcons.money, label: 'Total Cash', value: canViewMoney && cashTotal != null ? formatMoney(cashTotal!, symbol: currencySymbol, compact: true) : '—', secondary: 'cash position', onTap: canViewMoney ? () => context.goNamed('money') : null)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.green, icon: FulusIcons.sell, label: 'Today’s Sales', value: _salesCount.toString(), secondary: formatMoney(_salesTotal, symbol: currencySymbol, compact: true), onTap: canViewReports ? () => context.pushNamed('moreReportsSalesTransactions', extra: ReportsEngine().resolvePeriod(ReportPeriodKind.today)) : null)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.orange, icon: FulusIcons.stock, label: 'Low Stock', value: _lowStockCount.toString(), secondary: 'items', onTap: () => context.goNamed('stock'))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.purple, icon: FulusIcons.payments, label: 'Customer Credit', value: canViewMoney ? formatMoney(_creditTotal, symbol: currencySymbol, compact: true) : '—', secondary: 'outstanding', onTap: canViewMoney ? () => context.pushNamed('moneyCustomers') : null)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.teal, icon: FulusIcons.arrowUp, label: 'Expenses', value: canViewMoney ? formatMoney(_expensesTotal, symbol: currencySymbol, compact: true) : '—', secondary: 'today', onTap: canViewMoney ? () => context.goNamed('money') : null)),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: _HomeSellCard()),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // SliverFillRemaining gives this dashboard the remaining viewport height.
        // Use that space when it is available, while still allowing the cards to
        // grow beyond it when large text or narrow screens need more room.
        final availableHeight = constraints.maxHeight;
        final minRowHeight = 118.0;
        final rowGap = AppSpacing.sm;
        final responsiveRowHeight = availableHeight.isFinite && availableHeight > 0
            ? ((availableHeight - (2 * rowGap)) / 3).clamp(minRowHeight, double.infinity).toDouble()
            : minRowHeight;

        return Column(
          children: [
            for (final row in rows)
              if (row is Row)
                IntrinsicHeight(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: responsiveRowHeight),
                    child: row,
                  ),
                )
              else
                row,
          ],
        );
      },
    );
  }
}

class _HomeCompactCard extends StatelessWidget {
  const _HomeCompactCard({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.secondary,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final String secondary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.onColor(color);
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '$label, $value',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground, size: 36),
                const Spacer(),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.95),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSellCard extends StatelessWidget {
  const _HomeSellCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sell',
      child: Material(
        color: _HomeColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: () => context.goNamed('sell'),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  FulusIcons.sell,
                  color: Colors.white,
                  size: AppIconSize.base,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text(
                    'Sell',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeroSkeleton extends StatelessWidget {
  const _HomeHeroSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const minRowHeight = 118.0;
          final rowGap = AppSpacing.sm;
          final rowHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0
              ? ((constraints.maxHeight - (2 * rowGap)) / 3).clamp(minRowHeight, double.infinity).toDouble()
              : minRowHeight;

          return Column(
            children: [
              Row(children: [
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
              ]),
              SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
              ]),
              SizedBox(height: AppSpacing.sm),
              Row(children: [
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: FulusSkeletonBox(height: rowHeight)),
              ]),
            ],
          );
        },
      );
}

class _HomeColors {
  static const green = Color(0xFF0BBE6E);
  static const navy = Color(0xFF061B3A);
  static const blue = Color(0xFF1473E6);
  static const orange = Color(0xFFFF9F1C);
  static const purple = Color(0xFF7B3FF2);
  static const teal = Color(0xFF0DA8C4);
  static const muted = Color(0xFFB7C7DB);
}

final _businessProfileProvider = StreamProvider.autoDispose<BusinessProfile?>((ref) => ref.watch(businessSettingsRepositoryProvider).watchSettings());
