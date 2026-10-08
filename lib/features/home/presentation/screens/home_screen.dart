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
    final shortcuts = <_HomeShortcut>[
      if (canViewDashboardStats)
        const _HomeShortcut(
          color: AppColors.warning,
          icon: FulusIcons.receipt,
          art: FulusArt.receipt,
          label: 'Receipts',
          route: 'receiptHistory',
        ),
      if (canViewMoney)
        const _HomeShortcut(
          color: AppColors.customers,
          icon: FulusIcons.customers,
          art: FulusArt.customers,
          label: 'Customers',
          route: 'moneyCustomers',
        ),
      if (canViewReports)
        const _HomeShortcut(
          color: AppColors.reports,
          icon: FulusIcons.reports,
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
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Quick actions',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _HomeQuickActions(shortcuts: shortcuts),
      ],
    );
  }
}

class _HomeShortcut {
  const _HomeShortcut({
    required this.color,
    required this.icon,
    required this.art,
    required this.label,
    required this.route,
  });

  final Color color;
  final IconData icon;
  final FulusArt art;
  final String label;
  final String route;
}

/// Sell hero tile on the left, up to three stacked shortcuts on the right.
///
/// Row height is derived from the real window height so the block fits above
/// the bottom bar on short handheld POS screens and grows (up to a cap) on
/// taller phones. If the screen is shorter than the minimum, the page scrolls.
class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.shortcuts});

  final List<_HomeShortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    const gap = AppSpacing.md;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final minTile = textScale > 1.3 ? 80.0 : 68.0;
    // The hero always spans at least two shortcut rows so it never collapses
    // when permissions hide some shortcuts.
    final rows = shortcuts.length < 2 ? 2 : shortcuts.length;
    // ~420dp is the space taken by header, greeting, sales card, labels,
    // bottom bar and padding.
    // Give the action block enough height to visually fill the viewport while
    // preserving a small amount of intentional breathing room at the bottom.
    final ideal = (screenHeight - 330 - gap * (rows - 1)) / rows;
    final tileHeight = ideal.clamp(minTile, 180.0).toDouble();
    final blockHeight = tileHeight * rows + gap * (rows - 1);

    const hero = _HomeSellHero();
    if (shortcuts.isEmpty) {
      return SizedBox(height: blockHeight, child: hero);
    }

    return SizedBox(
      height: blockHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(flex: 9, child: hero),
          const SizedBox(width: gap),
          Expanded(
            flex: 11,
            child: Column(
              children: [
                for (var i = 0; i < shortcuts.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  Expanded(
                    child: _HomeShortcutTile(
                      icon: shortcuts[i].icon,
                      art: shortcuts[i].art,
                      color: shortcuts[i].color,
                      label: shortcuts[i].label,
                      onTap: () => context.goNamed(shortcuts[i].route),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeShortcutTile extends StatelessWidget {
  const _HomeShortcutTile({
    required this.icon,
    required this.art,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final FulusArt art;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.isDark(context)
        ? color.withValues(alpha: 0.18)
        : Color.alphaBlend(color.withValues(alpha: 0.14), Colors.white);

    return FulusPressable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Material(
        color: AppColors.surfaceOf(context),
        shape: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.7),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.hasBoundedHeight ? constraints.maxHeight : 96.0;
            final badge = (height - AppSpacing.md * 2).clamp(56.0, 72.0).toDouble();
            final glyph = badge * 0.68;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: badge,
                    height: badge,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                    ),
                    child: FulusArtIcon(
                      art,
                      size: glyph,
                      semanticLabel: label,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeSellHero extends StatelessWidget {
  const _HomeSellHero();

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    return FulusPressable(
      semanticsLabel: 'Sell, start a sale',
      onPressed: () => context.goNamed('sell'),
      child: Material(
        color: dark ? AppColors.success.withValues(alpha: 0.12) : AppColors.successLight,
        shape: Border.all(
          color: AppColors.success.withValues(alpha: 0.22),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dark ? AppColors.success.withValues(alpha: 0.2) : AppColors.salesLight,
                      shape: BoxShape.circle,
                    ),
                    child: const FulusArtIcon(FulusArt.sell, size: 64),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Sell',
                    style: AppTypography.title.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ),
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
    final compact = MediaQuery.sizeOf(context).height < 640;
    final value = error || salesTotal == null ? '—' : formatMoney(salesTotal!, symbol: currencySymbol);
    final count = error || salesCount == null
        ? 'Sales data unavailable'
        : '${salesCount!} sale${salesCount == 1 ? '' : 's'} today';
    const onGreen = Colors.white;
    final onGreenMuted = Colors.white.withValues(alpha: 0.88);

    return Semantics(
      label: 'Today’s sales, $value, $count',
      child: SizedBox(
        width: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 152 : 180),
          child: Material(
            color: AppColors.salesStrong,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.xl - AppSpacing.xs,
                vertical: compact ? AppSpacing.md : AppSpacing.lg + AppSpacing.xs,
              ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Today’s sales',
                  style: AppTypography.subheading.copyWith(color: onGreenMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTypography.display.copyWith(
                      color: onGreen,
                      fontSize: compact ? 32 : 40,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: onGreenMuted, fontSize: 15),
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
