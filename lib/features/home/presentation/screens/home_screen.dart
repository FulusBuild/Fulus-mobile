import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/money/money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_art.dart';
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
  }

  Future<void> _refresh() async {
    setState(_load);
    await _heroFuture;
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
                        padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HomeHeader(
                                businessName: ref.watch(_businessProfileProvider).value?.businessName.trim() ?? '',
                                locationName: _activeLocationName(ref),
                                greeting: 'Good ${_greeting()}, ${_displayName(ref)}',
                                onSwitchLocation: widget.isOwner ? () => _showLocationSwitcher(context) : null,
                                onSwitchAccount: () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => const IdentityPickerScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpacing.lg),
                        sliver: SliverToBoxAdapter(
                          child: _HomeDashboardHydration(
                            heroFuture: _heroFuture,
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
                        art: FulusArt.locations,
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

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
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
    required this.greeting,
    required this.onSwitchLocation,
    required this.onSwitchAccount,
  });

  final String businessName;
  final String? locationName;
  final String greeting;
  final VoidCallback? onSwitchLocation;
  final VoidCallback onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 640;
    final primaryText = AppColors.textPrimaryOf(context);
    final secondaryText = AppColors.textSecondaryOf(context);
    final hasLocation = locationName != null && locationName!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    businessName.isEmpty ? 'Fulus' : businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyLarge.copyWith(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hasLocation)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: onSwitchLocation,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FulusIcons.locations, size: 16, color: secondaryText),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                locationName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (onSwitchLocation != null) ...[
                              const SizedBox(width: 2),
                              Icon(FulusIcons.swap, size: 16, color: secondaryText),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FulusIconButton(
              icon: FulusIcons.people,
              tooltip: 'Switch employee',
              onPressed: onSwitchAccount,
            ),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        Text(
          greeting,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title.copyWith(
            color: primaryText,
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _HomeDashboardHydration extends StatefulWidget {
  const _HomeDashboardHydration({
    required this.heroFuture,
    required this.currencySymbol,
    required this.canViewDashboardStats,
    required this.canViewMoney,
    required this.canViewReports,
    required this.onRetry,
  });

  final Future<HomeHeroState> heroFuture;
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
  bool _heroError = false;

  @override
  void initState() {
    super.initState();
    // Start the local hero read immediately; the dashboard renders its
    // skeleton until the repository result is ready.
    widget.heroFuture.then(_setHero, onError: _setHeroError);  }

  @override
  void didUpdateWidget(covariant _HomeDashboardHydration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroFuture != widget.heroFuture) {
      _hero = null;
      _heroError = false;
      widget.heroFuture.then(_setHero, onError: _setHeroError);
    }
  }

  void _setHero(HomeHeroState value) {
    if (mounted) setState(() { _hero = value; _heroError = false; });
  }

  void _setHeroError(Object _, StackTrace __) {
    if (mounted) setState(() => _heroError = true);
  }

  @override
  Widget build(BuildContext context) {
    return _HomeMockupDashboard(
      hero: _hero,
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
    required this.heroError,
    required this.currencySymbol,
    required this.canViewDashboardStats,
    required this.canViewMoney,
    required this.canViewReports,
  });

  final HomeHeroState? hero;
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
    // Equal-tile grid: Sell is always available, the rest follow permissions.
    final shortcuts = <_HomeShortcut>[
      const _HomeShortcut(
        art: FulusArt.sell,
        label: 'Sell',
        route: 'sell',
      ),
      if (canViewDashboardStats)
        const _HomeShortcut(
          art: FulusArt.receipt,
          label: 'Receipts',
          route: 'receiptHistory',
        ),
      if (canViewMoney)
        const _HomeShortcut(
          art: FulusArt.customers,
          label: 'Customers',
          route: 'moneyCustomers',
        ),
      if (canViewReports)
        const _HomeShortcut(
          art: FulusArt.reports,
          label: 'Reports',
          route: 'moreReports',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSalesHeroCard(
          salesTotal: _salesTotal,
          salesCount: _salesCount,
          error: heroError,
          currencySymbol: currencySymbol,
        ),
        const SizedBox(height: AppSpacing.xxl + AppSpacing.sm),
        Text(
          'Quick actions',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _HomeQuickActions(shortcuts: shortcuts),
      ],
    );
  }
}

class _HomeShortcut {
  const _HomeShortcut({
    required this.art,
    required this.label,
    required this.route,
  });

  final FulusArt art;
  final String label;
  final String route;
}

/// Equal-size action tiles in a two-column grid (Sell, Receipts, Customers,
/// Reports). Every tile shares one size; hidden shortcuts simply leave an empty
/// cell so the remaining tiles never stretch.
///
/// Tile height is derived from the real window height so the block fills the
/// space above the bottom bar on tall phones, stays within a sensible cap, and
/// lets the page scroll on very short handheld POS screens.
class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.shortcuts});

  final List<_HomeShortcut> shortcuts;

  static const _columns = 2;

  @override
  Widget build(BuildContext context) {
    const gap = AppSpacing.md;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final minTile = textScale > 1.3 ? 144.0 : 120.0;
    final rowCount = (shortcuts.length / _columns).ceil().clamp(1, 4).toInt();
    // Reserve space for the system bars, header, greeting, sales card, section
    // label, bottom bar and a little breathing room.
    final ideal = (screenHeight - 520 - gap * (rowCount - 1)) / rowCount;
    final tileHeight = ideal.clamp(minTile, 190.0).toDouble();

    return Column(
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: gap),
          SizedBox(
            height: tileHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < _columns; col++) ...[
                  if (col > 0) const SizedBox(width: gap),
                  Expanded(child: _tileAt(context, row * _columns + col)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tileAt(BuildContext context, int index) {
    if (index >= shortcuts.length) return const SizedBox.shrink();
    final shortcut = shortcuts[index];
    return _HomeActionTile(
      art: shortcut.art,
      label: shortcut.label,
      onTap: () => context.goNamed(shortcut.route),
    );
  }
}

/// One rounded action tile: existing Fulus artwork on a plain surface (no
/// icon background) with the label underneath.
class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    required this.art,
    required this.label,
    required this.onTap,
  });

  final FulusArt art;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);

    return FulusPressable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: dark ? Border.all(color: AppColors.borderOf(context)) : null,
          boxShadow: AppElevation.cardOf(context),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FulusArtIcon(art, size: 56),
            const SizedBox(height: AppSpacing.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
    final compact = MediaQuery.sizeOf(context).height < 640;
    final value = error || salesTotal == null ? '—' : formatMoney(salesTotal!, symbol: currencySymbol);
    final count = error || salesCount == null
        ? 'Sales data unavailable'
        : '${salesCount!} sale${salesCount == 1 ? '' : 's'} today';
    const onPrimary = Colors.white;
    final onPrimaryMuted = Colors.white.withValues(alpha: 0.88);

    return Semantics(
      label: 'Today’s sales, $value, $count',
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 128 : 148),
          child: Material(
            color: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl - AppSpacing.xs,
                vertical: compact ? AppSpacing.lg : AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'TODAY’S SALES',
                    style: AppTypography.label.copyWith(
                      color: onPrimaryMuted,
                      letterSpacing: 0.8,
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
                        color: onPrimary,
                        fontSize: compact ? 36 : 44,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 5,
                      ),
                      child: Text(
                        count,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.label.copyWith(color: onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _businessProfileProvider = StreamProvider.autoDispose<BusinessProfile?>((ref) => ref.watch(businessSettingsRepositoryProvider).watchSettings());
