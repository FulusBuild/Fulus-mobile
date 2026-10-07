import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/money/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/dashboard_summary.dart';
import '../../../../domain/entities/location.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../auth/presentation/screens/identity_picker_screen.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;

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
    _noticesFuture = showBusinessWide
        ? locationFuture.then((locationId) => repo.getSecondaryNotices(
              locationId: locationId,
              max: 3,
            ))
        : Future.value(
            const SecondaryNoticeSelection(
              shown: <SecondaryNotice>[],
              overflowCount: 0,
            ),
          );
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_heroFuture, _noticesFuture]);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentAuthUserId != widget.currentAuthUserId ||
        oldWidget.isOwner != widget.isOwner ||
        oldWidget.canViewDashboardStats != widget.canViewDashboardStats ||
        oldWidget.canViewMoney != widget.canViewMoney ||
        oldWidget.canViewReports != widget.canViewReports) {
      // StatefulShellRoute keeps Home alive across identity changes. Reload
      // all user-sensitive futures so a newly selected employee cannot
      // inherit the previous employee's dashboard data.
      _load();
    }
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
                                onSwitchLocation: widget.isOwner ? () => _showLocationSwitcher(context) : null,
                                onSwitchAccount: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => const IdentityPickerScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                '${greetingForHour(DateTime.now().hour)}, ${_displayName(ref)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.heading.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                  fontWeight: FontWeight.w700,
                                ),
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
                            currencySymbol: currencySymbol,
                            canViewDashboardStats: widget.isOwner || widget.canViewDashboardStats,
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
    final locations = ref.watch(_homeLocationsProvider).value;
    if (activeId == null || locations == null) return null;
    for (final location in locations) {
      if (location.localId == activeId) return location.name;
    }
    return null;
  }

  Future<void> _showLocationSwitcher(BuildContext context) async {
    final locations = await ref.read(_homeLocationsProvider.future);
    final activeId = await ref.read(activeLocationIdProvider.future);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      builder: (sheetContext) {
        var switchingId = <String>{};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> select(Location location) async {
              if (location.localId == activeId || switchingId.isNotEmpty) return;
              setSheetState(() => switchingId = {location.localId});
              try {
                await ref.read(switchActiveLocationProvider)(location.localId);
                ref.invalidate(activeLocationIdProvider);
                ref.read(dataRefreshSignalProvider.notifier).state++;
                unawaited(ref.read(syncServiceProvider).refreshAfterContextChange());
                if (context.mounted) Navigator.of(context).pop();
                if (mounted) {
                  showFulusSnackbar(context, message: 'Now viewing ' + location.name + '.');
                }
              } catch (error) {
                if (context.mounted) {
                  showFulusSnackbar(
                    context,
                    message: error is StateError ? error.message : "Couldn't switch locations. Try again.",
                  );
                }
                if (context.mounted) setSheetState(() => switchingId = <String>{});
              }
            }

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                children: [
                  Text(
                    'Switch location',
                    style: AppTypography.heading.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Choose where you are working now.',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final location in locations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: FulusActionTile(
                        icon: FulusIcons.locations,
                        label: location.name,
                        subtitle: location.localId == activeId ? 'Current location' : 'Switch here',
                        onTap: switchingId.isEmpty ? () => select(location) : null,
                        trailing: location.localId == activeId
                            ? const Icon(FulusIcons.check)
                            : null,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _displayName(WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final isOwner = user == null || user.role == AuthRole.owner;
    if (isOwner) return user?.fullName.trim().isNotEmpty == true ? user!.fullName.trim() : 'there';
    return user.fullName.trim().isNotEmpty == true ? user.fullName.trim() : 'there';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.businessName,
    required this.locationName,
    required this.onSwitchLocation,
    required this.onSwitchAccount,
  });

  final String businessName;
  final String? locationName;
  final VoidCallback? onSwitchLocation;
  final VoidCallback onSwitchAccount;

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
                style: AppTypography.subheading.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (locationName != null && locationName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(FulusIcons.locations, size: 16, color: AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        locationName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (onSwitchLocation != null)
                      IconButton(
                        tooltip: 'Switch location',
                        onPressed: onSwitchLocation,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        icon: Icon(FulusIcons.swap, size: 20, color: AppColors.textSecondaryOf(context)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        FulusIconButton(
          icon: FulusIcons.switchAccount,
          tooltip: 'Switch employee',
          onPressed: onSwitchAccount,
        ),
      ],
    );
  }
}

class _HomeDashboardHydration extends StatefulWidget {
  const _HomeDashboardHydration({
    required this.heroFuture,
    required this.noticesFuture,
    required this.currencySymbol,
    required this.canViewDashboardStats,
    required this.canViewMoney,
    required this.canViewReports,
    required this.onRetry,
  });

  final Future<HomeHeroState> heroFuture;
  final Future<SecondaryNoticeSelection> noticesFuture;
  final String currencySymbol;
  final bool canViewDashboardStats;
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

  @override
  void initState() {
    super.initState();
    // Start all independent local reads together. None waits for another
    // FutureBuilder to build before its own future is observed.
    widget.heroFuture.then(_setHero, onError: _setHeroError);
    widget.noticesFuture.then(_setNotices, onError: _setNoticesError);
  }

  @override
  void didUpdateWidget(covariant _HomeDashboardHydration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroFuture != widget.heroFuture ||
        oldWidget.noticesFuture != widget.noticesFuture) {
      _hero = null;
      _noticeSelection = null;
      _heroError = false;
      _noticesError = false;
      widget.heroFuture.then(_setHero, onError: _setHeroError);
      widget.noticesFuture.then(_setNotices, onError: _setNoticesError);
    }
  }

  void _setHero(HomeHeroState value) {
    if (mounted) setState(() { _hero = value; _heroError = false; });
  }

  void _setNotices(SecondaryNoticeSelection value) {
    if (mounted) setState(() { _noticeSelection = value; _noticesError = false; });
  }

  void _setHeroError(Object _, StackTrace __) {
    if (mounted) setState(() => _heroError = true);
  }

  void _setNoticesError(Object _, StackTrace __) {
    if (mounted) setState(() => _noticesError = true);
  }

  @override
  Widget build(BuildContext context) {
    return _HomeMockupDashboard(
      hero: _hero,
      notices: _noticeSelection?.shown ?? const <SecondaryNotice>[],
      noticesError: _noticesError,
      heroError: _heroError,
      currencySymbol: widget.currencySymbol,
      canViewDashboardStats: widget.canViewDashboardStats,
      canViewMoney: widget.canViewMoney,
      canViewReports: widget.canViewReports,
    );
  }
}

class _HomeMockupDashboard extends StatelessWidget {
  const _HomeMockupDashboard({
    required this.hero,
    required this.notices,
    required this.noticesError,
    required this.heroError,
    required this.currencySymbol,
    required this.canViewDashboardStats,
    required this.canViewMoney,
    required this.canViewReports,
  });

  final HomeHeroState? hero;
  final List<SecondaryNotice> notices;
  final bool noticesError;
  final bool heroError;
  final String currencySymbol;
  final bool canViewDashboardStats;
  final bool canViewMoney;
  final bool canViewReports;

  Money? get _salesTotal => switch (hero) {
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

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      const _HomeActionCell(color: AppColors.primary, icon: FulusIcons.sell, label: 'Sell', route: 'sell'),
      if (canViewDashboardStats)
        const _HomeActionCell(color: AppColors.sales, icon: FulusIcons.receipt, label: 'Receipts', route: 'receiptHistory'),
      if (canViewMoney)
        const _HomeActionCell(color: AppColors.customers, icon: FulusIcons.customers, label: 'Customer', route: 'moneyCustomers'),
      if (canViewReports)
        const _HomeActionCell(color: AppColors.reports, icon: FulusIcons.reports, label: 'Reports', route: 'moreReports'),
    ];

    return Column(
      children: [
        _HomeSalesHeroCard(
          salesTotal: _salesTotal,
          salesCount: _salesCount,
          error: heroError,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = AppSpacing.sm;
            final width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in actions)
                  SizedBox(width: width, height: width.clamp(112.0, 180.0), child: action),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HomeActionCell extends StatelessWidget {
  const _HomeActionCell({
    required this.color,
    required this.icon,
    required this.label,
    required this.route,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => context.goNamed(route),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: color),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSalesHeroCard extends StatelessWidget {
  const _HomeSalesHeroCard({
    required this.salesTotal,
    required this.salesCount,
    required this.error,
    required this.currencySymbol,
  });

  final Money? salesTotal;
  final int? salesCount;
  final bool error;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final value = error || salesTotal == null ? '—' : formatMoney(salesTotal!, symbol: currencySymbol);
    final count = error || salesCount == null
        ? 'Sales data unavailable'
        : '${salesCount!} sale${salesCount == 1 ? '' : 's'} today';

    return Semantics(
      label: 'Today’s sales, $value, $count',
      child: Material(
        color: AppColors.sales,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today’s Sales',
                style: AppTypography.subheading.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                count,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _businessProfileProvider = StreamProvider.autoDispose<BusinessProfile?>((ref) => ref.watch(businessSettingsRepositoryProvider).watchSettings());
