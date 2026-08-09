import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';

/// The global app shell — Component Library 5.5's bottom bar,
/// "visible from every screen... the product's spine." Wraps whichever
/// branch [navigationShell] is currently showing (Home/Stock/Sell/
/// Money/More, each keeping its own independent navigation stack —
/// go_router's `StatefulShellRoute.indexedStack`, wired in router.dart)
/// in a persistent [Scaffold] + bottom nav.
///
/// This widget owns navigation chrome only — it has no opinion on auth;
/// router.dart gates the entire shell behind a signed-in check before
/// ever building this, so by the time this widget exists, a session is
/// assumed to be real. [isOwner] is the one piece of session state it
/// does need directly, though: Volume 2's Decision 6 — "the navigation
/// structure itself is generated per role, so an employee login never
/// renders tabs it doesn't need" — Money and More are both owner-only
/// (Volume 9: "An Employee login never sees Money, Reports, Employees,
/// or Settings at all — not grayed out, not present-but-locked, simply
/// not rendered"), so an Employee session gets a 3-item bar (Home,
/// Stock, Sell), not a 5-item bar with two disabled buttons. Hiding the
/// buttons is only half of Decision 6's enforcement — router.dart's
/// top-level `redirect` is the other half, blocking direct navigation
/// to `/money` or `/more` for an Employee session even if nothing in
/// this UI offers a way to tap there.
///
/// Stock's employee-visibility is genuinely ambiguous in the source
/// material — Decision 6 and Volume 9 both name Money, Reports,
/// Employees, and Settings explicitly as hidden, and neither ever names
/// Stock one way or the other. Volume 9 does say an Employee login can
/// always "request... a stock adjustment," which reads as assuming some
/// stock-related capability stays reachable. Kept visible here on that
/// basis — the more conservative reading between "explicitly hidden"
/// and "never mentioned," not a confirmed decision.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({super.key, required this.navigationShell, required this.isOwner});

  final StatefulNavigationShell navigationShell;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _FulusBottomNav(
        currentIndex: navigationShell.currentIndex,
        isOwner: isOwner,
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
/// sites. All five branches always exist in the router regardless of
/// role (StatefulShellRoute branches are fixed at construction, not
/// reactive) — what changes per role is only which of these indices
/// [_FulusBottomNav] renders a button for, plus router.dart's redirect
/// guard for the two an Employee shouldn't reach at all.
class FulusNavBranch {
  FulusNavBranch._();
  static const home = 0;
  static const stock = 1;
  static const sell = 2;
  static const money = 3;
  static const more = 4;
}

class _FulusBottomNav extends StatelessWidget {
  const _FulusBottomNav({required this.currentIndex, required this.onTap, required this.isOwner});

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isOwner;

  static const _barHeight = 64.0;
  static const _sellDiameter = 54.0;

  @override
  Widget build(BuildContext context) {
    final leftItems = [
      _NavItem(
        icon: Icons.home_outlined,
        filledIcon: Icons.home,
        label: 'Home',
        selected: currentIndex == FulusNavBranch.home,
        onTap: () => onTap(FulusNavBranch.home),
      ),
      _NavItem(
        icon: Icons.inventory_2_outlined,
        filledIcon: Icons.inventory_2,
        label: 'Stock',
        selected: currentIndex == FulusNavBranch.stock,
        onTap: () => onTap(FulusNavBranch.stock),
      ),
    ];
    // Empty for an Employee session — see this class's own doc comment
    // and FulusAppShell's for why. An empty right side still keeps the
    // Sell button centered (below, both halves are equal-width
    // Expandeds regardless of how many items populate them), it just
    // leaves the right half of the bar blank rather than attempting to
    // rebalance Home/Stock across the full width — the simplest correct
    // layout without a device to visually check a rebalanced version
    // against.
    final rightItems = isOwner
        ? [
            _NavItem(
              icon: Icons.account_balance_wallet_outlined,
              filledIcon: Icons.account_balance_wallet,
              label: 'Money',
              selected: currentIndex == FulusNavBranch.money,
              onTap: () => onTap(FulusNavBranch.money),
            ),
            _NavItem(
              icon: Icons.more_horiz,
              filledIcon: Icons.more_horiz,
              label: 'More',
              selected: currentIndex == FulusNavBranch.more,
              onTap: () => onTap(FulusNavBranch.more),
            ),
          ]
        : const <Widget>[];

    // Extra headroom above the bar so the Sell button's circle can
    // "break the baseline" (5.5) rather than sit flush inside the bar
    // like the other items. The exact overlap amount below is a
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
                  // Left and right halves are each an Expanded wrapping
                  // an evenly-spaced Row of whatever items that side
                  // has — this is what keeps the center gap (and the
                  // Sell button floating above it) genuinely centered
                  // regardless of whether the right side has 2 items
                  // (Owner) or 0 (Employee), rather than the gap
                  // drifting off-center if left/right item counts
                  // differ.
                  Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: leftItems),
                  ),
                  const SizedBox(width: _sellDiameter + AppSpacing.md),
                  Expanded(
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: rightItems),
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
