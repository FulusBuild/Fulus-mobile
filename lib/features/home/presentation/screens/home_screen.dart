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
                    // Keep the dashboard vertically scrollable so larger cards remain accessible
                    // on smaller screens without adding extra whitespace above the navbar.
                    physics: const AlwaysScrollableScrollPhysics(),
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
                        padding: EdgeInsets.fromLTRB(inset, 0, inset, 0),
                        sliver: SliverToBoxAdapter(
                          child: _HomeDashboardHydration(
                            heroFuture: _heroFuture,
                            noticesFuture: _noticesFuture,
                            activityFuture: _activityFuture,
                            cashFuture: _cashFuture,
                            currencySymbol: currencySymbol,
                            canViewMoney: widget.isOwner || widget.canViewMoney,
                            canViewReports: widget.isOwner || widget.canViewReports,
                            onRetry: _refresh,
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

class _HomeDashboardHydration extends StatefulWidget {
  const _HomeDashboardHydration({
    required this.heroFuture,
    required this.noticesFuture,
    required this.activityFuture,
    required this.cashFuture,
    required this.currencySymbol,
    required this.canViewMoney,
    required this.canViewReports,
    required this.onRetry,
  });

  final Future<HomeHeroState> heroFuture;
  final Future<SecondaryNoticeSelection> noticesFuture;
  final Future<List<MoneyTransaction>> activityFuture;
  final Future<double> cashFuture;
  final String currencySymbol;
  final bool canViewMoney;
  final bool canViewReports;
  final VoidCallback onRetry;

  @override
  State<_HomeDashboardHydration> createState() => _HomeDashboardHydrationState();
}

class _HomeDashboardHydrationState extends State<_HomeDashboardHydration> {
  HomeHeroState? _hero;
  SecondaryNoticeSelection? _noticeSelection;
  List<MoneyTransaction> _activity = const [];
  double? _cashTotal;

  @override
  void initState() {
    super.initState();
    // Start all independent local reads together. None waits for another
    // FutureBuilder to build before its own future is observed.
    widget.heroFuture.then(_setHero, onError: _ignoreFutureError);
    widget.noticesFuture.then(_setNotices, onError: _ignoreFutureError);
    widget.activityFuture.then(_setActivity, onError: _ignoreFutureError);
    widget.cashFuture.then(_setCash, onError: _ignoreFutureError);
  }

  @override
  void didUpdateWidget(covariant _HomeDashboardHydration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroFuture != widget.heroFuture ||
        oldWidget.noticesFuture != widget.noticesFuture ||
        oldWidget.activityFuture != widget.activityFuture ||
        oldWidget.cashFuture != widget.cashFuture) {
      _hero = null;
      _noticeSelection = null;
      _activity = const [];
      _cashTotal = null;
      widget.heroFuture.then(_setHero, onError: _ignoreFutureError);
      widget.noticesFuture.then(_setNotices, onError: _ignoreFutureError);
      widget.activityFuture.then(_setActivity, onError: _ignoreFutureError);
      widget.cashFuture.then(_setCash, onError: _ignoreFutureError);
    }
  }

  void _setHero(HomeHeroState value) {
    if (mounted) setState(() => _hero = value);
  }

  void _setNotices(SecondaryNoticeSelection value) {
    if (mounted) setState(() => _noticeSelection = value);
  }

  void _setActivity(List<MoneyTransaction> value) {
    if (mounted) setState(() => _activity = value);
  }

  void _setCash(double value) {
    if (mounted) setState(() => _cashTotal = value);
  }

  void _ignoreFutureError(Object _, StackTrace __) {
    // A failed local section must not remove the rest of the dashboard.
  }

  @override
  Widget build(BuildContext context) {
    return _HomeMockupDashboard(
      hero: _hero,
      notices: _noticeSelection?.shown ?? const <SecondaryNotice>[],
      activity: _activity,
      cashTotal: _cashTotal,
      currencySymbol: widget.currencySymbol,
      canViewMoney: widget.canViewMoney,
      canViewReports: widget.canViewReports,
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
  final HomeHeroState? hero;
  final List<SecondaryNotice> notices;
  final List<MoneyTransaction> activity;
  final double? cashTotal;
  final String currencySymbol;
  final bool canViewMoney;
  final bool canViewReports;

  double? get _salesTotal => switch (hero) {
    null => null,
    NotYetOpenedHero(:final yesterdayTotal) => yesterdayTotal,
    OpenHero(:final todayTotal) => todayTotal,
    ClosedHero(:final finalTotal) => finalTotal,
    EmployeeShiftHero(:final shiftTotal) => shiftTotal,
  };
  int? get _salesCount => switch (hero) {
    null => null,
    NotYetOpenedHero(:final yesterdaySalesCount) => yesterdaySalesCount,
    OpenHero(:final todaySalesCount) => todaySalesCount,
    ClosedHero(:final finalSalesCount) => finalSalesCount,
    EmployeeShiftHero(:final shiftSalesCount) => shiftSalesCount,
  };
  int get _lowStockCount => notices.where((n) => n.type == SecondaryNoticeType.lowStock).fold<int>(0, (sum, n) => sum + n.value.toInt());
  double get _creditTotal => notices.where((n) => n.type == SecondaryNoticeType.pendingCredit).fold<double>(0, (sum, n) => sum + n.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.blue, icon: FulusIcons.cashBalance, label: 'Total Cash', value: canViewMoney && cashTotal != null ? formatMoney(cashTotal!, symbol: currencySymbol, compact: true) : '—', secondary: 'cash position', onTap: canViewMoney ? () => context.goNamed('money') : null)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.green, icon: FulusIcons.sell, label: 'Today’s Sales', value: _salesCount?.toString() ?? '—', secondary: _salesTotal == null ? 'waiting for local data' : formatMoney(_salesTotal!, symbol: currencySymbol, compact: true), onTap: canViewReports ? () => context.pushNamed('moreReportsSalesTransactions', extra: ReportsEngine().resolvePeriod(ReportPeriodKind.today)) : null)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.orange, icon: FulusIcons.stock, label: 'Low Stock', value: _lowStockCount.toString(), secondary: 'items', onTap: () => context.goNamed('stock'))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.purple, icon: FulusIcons.customers, label: 'Customer Credit', value: canViewMoney ? formatMoney(_creditTotal, symbol: currencySymbol, compact: true) : '—', secondary: 'outstanding', onTap: canViewMoney ? () => context.pushNamed('moneyCustomers') : null)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeReportCard(canViewReports: canViewReports)),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: _HomeSellCard()),
        ],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // The dashboard lives inside a scrollable sliver, so its vertical
        // constraint is not a reliable viewport measurement. The Home card
        // family therefore owns a width-based aspect ratio rather than
        // deriving an icon size from the available width.
        const dashboardBottomGap = AppSpacing.md * 3;
        const homeCardAspectRatio = 1.0;
        const minRowHeight = 180.0;
        const rowGap = AppSpacing.sm;
        final cardWidth = (constraints.maxWidth - rowGap) / 2;
        final widthDrivenRowHeight = (cardWidth / homeCardAspectRatio)
            .clamp(minRowHeight, double.infinity)
            .toDouble();

        return Column(
          children: [
            for (final row in rows)
              if (row is Row)
                SizedBox(
                  height: widthDrivenRowHeight,
                  child: row,
                )
              else
                row,
            const SizedBox(height: dashboardBottomGap),
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
            child: FulusMetricCardColumn(
              icon: icon,
              iconColor: foreground,
              children: [
                Text(
                  label,
                  maxLines: 1,
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
          )
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
          child: const Center(
            child: Text(
              'Sell',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 90,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeReportCard extends StatelessWidget {
  const _HomeReportCard({required this.canViewReports});

  final bool canViewReports;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: canViewReports,
      enabled: canViewReports,
      label: 'Reports',
      child: Material(
        color: _HomeColors.teal,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: canViewReports ? () => context.goNamed('moreReports') : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FulusMetricCardColumn(
              icon: FulusIcons.reports,
              iconColor: Colors.white,
              children: const [
                Text(
                  'Reports',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
