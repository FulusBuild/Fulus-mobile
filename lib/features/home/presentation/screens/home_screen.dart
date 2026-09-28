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
import '../../../../domain/entities/location.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider, moneyRepositoryProvider;

final _homeLocationsProvider = StreamProvider<List<Location>>((ref) =>
    ref.watch(locationRepositoryProvider).watchLocations());

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
  late Future<double> _cashFuture;

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
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture, _cashFuture]);
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
                                locationName: _activeLocationName(ref),
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
  String? _activeLocationName(WidgetRef ref) {
    final activeId = ref.watch(activeLocationIdProvider).value;
    final locations = ref.watch(_homeLocationsProvider).valueOrNull;
    if (activeId == null || locations == null) return null;
    for (final location in locations) {
      if (location.localId == activeId) return location.name;
    }
    return null;
  }

  String _displayName(WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final isOwner = user == null || user.role == AuthRole.owner;
    if (isOwner) return user?.fullName.trim().isNotEmpty == true ? user!.fullName.trim() : 'there';
    return user.fullName.trim().isNotEmpty == true ? user.fullName.trim() : 'there';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.businessName, required this.locationName});

  final String businessName;
  final String? locationName;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                businessName.isEmpty ? 'Fulus' : businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (locationName != null && locationName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(FulusIcons.locations, size: 16, color: _HomeColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        locationName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _HomeColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
    required this.cashFuture,
    required this.currencySymbol,
    required this.canViewMoney,
    required this.canViewReports,
    required this.onRetry,
  });

  final Future<HomeHeroState> heroFuture;
  final Future<SecondaryNoticeSelection> noticesFuture;
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
  bool _heroError = false;
  bool _noticesError = false;
  bool _cashError = false;
  double? _cashTotal;

  @override
  void initState() {
    super.initState();
    // Start all independent local reads together. None waits for another
    // FutureBuilder to build before its own future is observed.
    widget.heroFuture.then(_setHero, onError: _setHeroError);
    widget.noticesFuture.then(_setNotices, onError: _setNoticesError);
    widget.cashFuture.then(_setCash, onError: _setCashError);
  }

  @override
  void didUpdateWidget(covariant _HomeDashboardHydration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroFuture != widget.heroFuture ||
        oldWidget.noticesFuture != widget.noticesFuture ||
        oldWidget.cashFuture != widget.cashFuture) {
      _hero = null;
      _noticeSelection = null;
      _cashTotal = null;
      _heroError = false;
      _noticesError = false;
      _cashError = false;
      widget.heroFuture.then(_setHero, onError: _setHeroError);
      widget.noticesFuture.then(_setNotices, onError: _setNoticesError);
      widget.cashFuture.then(_setCash, onError: _setCashError);
    }
  }

  void _setHero(HomeHeroState value) {
    if (mounted) setState(() { _hero = value; _heroError = false; });
  }

  void _setNotices(SecondaryNoticeSelection value) {
    if (mounted) setState(() { _noticeSelection = value; _noticesError = false; });
  }

  void _setCash(double value) {
    if (mounted) setState(() { _cashTotal = value; _cashError = false; });
  }

  void _setHeroError(Object _, StackTrace __) {
    if (mounted) setState(() => _heroError = true);
  }

  void _setNoticesError(Object _, StackTrace __) {
    if (mounted) setState(() => _noticesError = true);
  }

  void _setCashError(Object _, StackTrace __) {
    if (mounted) setState(() => _cashError = true);
  }

  @override
  Widget build(BuildContext context) {
    return _HomeMockupDashboard(
      hero: _hero,
      notices: _noticeSelection?.shown ?? const <SecondaryNotice>[],
      noticesError: _noticesError,
      heroError: _heroError,
      cashError: _cashError,
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
    required this.cashTotal,
    required this.noticesError,
    required this.heroError,
    required this.cashError,
    required this.currencySymbol,
    required this.canViewMoney,
    required this.canViewReports,
  });
  final HomeHeroState? hero;
  final List<SecondaryNotice> notices;
  final bool noticesError;
  final bool heroError;
  final bool cashError;
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
  int? get _lowStockCount => noticesError ? null : notices.where((n) => n.type == SecondaryNoticeType.lowStock).fold<int>(0, (sum, n) => sum + n.value.toInt());
  double? get _creditTotal => noticesError ? null : notices.where((n) => n.type == SecondaryNoticeType.pendingCredit).fold<double>(0, (sum, n) => sum + n.value.toDouble());

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: _HomeSalesHeroCard(
              salesTotal: _salesTotal,
              salesCount: _salesCount,
              error: heroError,
              currencySymbol: currencySymbol,
              onTap: canViewReports
                  ? () => context.pushNamed(
                        'moreReportsSalesTransactions',
                        extra: ReportsEngine().resolvePeriod(ReportPeriodKind.today),
                      )
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 1,
            child: _HomeCompactCard(
              color: _HomeColors.blue,
              icon: FulusIcons.cashBalance,
              label: 'Business Balance',
              value: canViewMoney && cashError
                  ? '—'
                  : canViewMoney && cashTotal != null
                      ? formatMoney(cashTotal!, symbol: currencySymbol, compact: true)
                      : '—',
              secondary: 'available',
              onTap: canViewMoney ? () => context.goNamed('money') : null,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HomeCompactCard(color: _HomeColors.orange, icon: FulusIcons.stock, label: 'Low Stock', value: _lowStockCount?.toString() ?? '—', secondary: 'items', onTap: () => context.goNamed('stock'))),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _HomeCompactCard(color: _HomeColors.purple, icon: FulusIcons.customers, label: 'Customer Credit', value: canViewMoney && _creditTotal != null ? formatMoney(_creditTotal!, symbol: currencySymbol, compact: true) : '—', secondary: 'outstanding', onTap: canViewMoney ? () => context.pushNamed('moneyCustomers') : null)),
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

class _HomeSalesHeroCard extends StatelessWidget {
  const _HomeSalesHeroCard({
    required this.salesTotal,
    required this.salesCount,
    required this.error,
    required this.currencySymbol,
    required this.onTap,
  });

  final double? salesTotal;
  final int? salesCount;
  final bool error;
  final String currencySymbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final value = error || salesTotal == null
        ? '—'
        : formatMoney(salesTotal!, symbol: currencySymbol, compact: true);
    final count = error || salesCount == null
        ? 'Sales data unavailable'
        : '${salesCount!} sale${salesCount == 1 ? '' : 's'} today';

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: 'Today’s sales, $value, $count',
      child: Material(
        color: _HomeColors.green,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FulusMetricCardColumn(
              icon: FulusIcons.sell,
              iconColor: Colors.white,
              children: [
                const Text(
                  'Today’s Sales',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
