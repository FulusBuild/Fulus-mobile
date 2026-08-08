import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';

/// The global app shell — Component Library 5.5's five-destination
/// bottom bar, "visible from every screen... the product's spine."
/// Wraps whichever branch [navigationShell] is currently showing
/// (Home/Stock/Sell/Money/More, each keeping its own independent
/// navigation stack — go_router's `StatefulShellRoute.indexedStack`,
/// wired in router.dart) in a persistent [Scaffold] + bottom nav.
///
/// This widget owns navigation chrome only — it has no opinion on auth;
/// router.dart gates the entire shell behind a signed-in check before
/// ever building this, so by the time this widget exists, a session is
/// assumed to be real.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _FulusBottomNav(
        currentIndex: navigationShell.currentIndex,
        // `initialLocation: true` when re-tapping the already-active
        // tab pops that branch back to its own root, matching the
        // Bible's implicit assumption that tapping a nav icon always
        // means "take me to the top of this section" — go_router's own
        // documented behavior for this exact StatefulShellRoute pattern.
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// Branch indices, matching 5.5's stated icon order (Home, Stock, Sell,
/// Money, More) and router.dart's branch order — kept as named
/// constants here rather than magic numbers repeated at both call
/// sites.
class FulusNavBranch {
  FulusNavBranch._();
  static const home = 0;
  static const stock = 1;
  static const sell = 2;
  static const money = 3;
  static const more = 4;
}

class _FulusBottomNav extends StatelessWidget {
  const _FulusBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _barHeight = 64.0;
  static const _sellDiameter = 54.0;

  @override
  Widget build(BuildContext context) {
    // Extra headroom above the bar so the Sell button's circle can
    // "break the baseline" (5.5) rather than sit flush inside the bar
    // like the other four items. The exact overlap amount below is a
    // reasonable starting point, not visually verified on a device (no
    // Flutter toolchain was available while writing this) — worth a
    // quick look the first time this actually renders, and adjusting
    // the Positioned `top` value below if the circle reads as
    // crowding the bar rather than clearly floating above it.
    return SizedBox(
      height: _barHeight + (_sellDiameter * 0.45),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: _barHeight,
            decoration: BoxDecoration(color: AppColors.surfaceOf(context), boxShadow: AppElevation.liftOf(context)),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.home_outlined,
                      filledIcon: Icons.home,
                      label: 'Home',
                      selected: currentIndex == FulusNavBranch.home,
                      onTap: () => onTap(FulusNavBranch.home),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.inventory_2_outlined,
                      filledIcon: Icons.inventory_2,
                      label: 'Stock',
                      selected: currentIndex == FulusNavBranch.stock,
                      onTap: () => onTap(FulusNavBranch.stock),
                    ),
                  ),
                  // Reserved center gap — the Sell button floats above
                  // this space rather than sitting in the row itself.
                  const SizedBox(width: _sellDiameter + AppSpacing.md),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.account_balance_wallet_outlined,
                      filledIcon: Icons.account_balance_wallet,
                      label: 'Money',
                      selected: currentIndex == FulusNavBranch.money,
                      onTap: () => onTap(FulusNavBranch.money),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.more_horiz,
                      filledIcon: Icons.more_horiz,
                      label: 'More',
                      selected: currentIndex == FulusNavBranch.more,
                      onTap: () => onTap(FulusNavBranch.more),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: _SellNavItem(
              selected: currentIndex == FulusNavBranch.sell,
              onTap: () => onTap(FulusNavBranch.sell),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home/Stock/Money/More — the four ordinary destinations. "Active
/// state: filled icon + Primary colour + label weight stays the
/// same — filled-vs-outline is what actually signals selection, colour
/// reinforces it" (5.5) — hence swapping between [icon] (outline) and
/// [filledIcon] rather than only recoloring one fixed glyph. "Labels
/// always visible, never icon-only" (Product Bible Decision 55).
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.filledIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData filledIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryOf(context) : AppColors.textSecondaryOf(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouchTarget.minimum),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? filledIcon : icon, color: color, size: AppIconSize.base),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: color, fontSize: 11, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Sell destination — 5.5's one deliberate exception: "Elevated
/// 54dp circle, breaks the baseline... the one nav item allowed to look
/// different, because it's the one action the whole product exists to
/// make fast." Still carries a visible "Sell" label underneath, same as
/// every other item — the Bible's own component listing pairs
/// `point_of_sale` with the label "Sell" exactly like the other four,
/// so "looks different" means the elevated circle treatment, not an
/// exemption from the always-visible-label rule.
class _SellNavItem extends StatelessWidget {
  const _SellNavItem({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final circleColor = AppColors.primaryOf(context);
    final onCircleColor = AppColors.onPrimaryOf(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
              boxShadow: AppElevation.liftOf(context),
            ),
            child: Icon(Icons.point_of_sale, color: onCircleColor, size: AppIconSize.base),
          ),
          const SizedBox(height: 2),
          Text(
            'Sell',
            style: AppTypography.caption.copyWith(color: circleColor, fontSize: 11, height: 1),
          ),
        ],
      ),
    );
  }
}
