import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';
import '../sync/sync_status.dart';
import 'providers.dart';

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
///
/// Gap fix: Volume 2/Volume 12's persistent sync indicator — "same
/// place on every screen" — didn't exist anywhere. It couldn't live on
/// each screen's own AppBar: several screens (Home included) build no
/// AppBar at all, so "same place on every screen" can only genuinely
/// hold at the one layer that wraps literally every screen, which is
/// this shell. Rendered as a small overlay above [navigationShell]
/// rather than inside the Scaffold's own `appBar` slot, since that slot
/// belongs to each individual screen, not this shared shell.
///
/// Gap fix: a global "you're offline" indicator didn't exist either —
/// `connectivity_plus` (already a dependency) was only ever checked in
/// one place, Payment, to block Card/Mobile Money specifically. This is
/// a genuinely different signal from the sync indicator above: sync can
/// be (and by default is) turned off entirely while the device is still
/// online, and the device can go offline whether or not sync is even
/// enabled — conflating the two would misreport one or the other.
/// Rendered as a thin banner that pushes content down rather than an
/// overlay, since Volume 12's own rule for this state ("never a
/// full-screen interstitial... reassuring, not alarming") reads as
/// wanting it noticeable, not just a small icon someone has to go
/// looking for.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({super.key, required this.navigationShell, required this.isOwner});

  final StatefulNavigationShell navigationShell;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                navigationShell,
                const Positioned(top: 0, right: 0, child: SafeArea(child: _SyncStatusIndicator())),
              ],
            ),
          ),
        ],
      ),
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

/// A thin, dismissal-free banner — appears the moment the device goes
/// offline, disappears the moment it's back, no tap target of its own
/// (the sync indicator above is the tap target, for anyone who wants
/// more than "you're offline" — this is purely informational).
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(_isOnlineProvider).valueOrNull ?? true;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: isOnline
          ? const SizedBox(width: double.infinity)
          : SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: AppColors.textSecondaryOf(context),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_outlined, color: Colors.white, size: AppIconSize.dense),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      "You're offline — your work is saved and will sync when you're back.",
                      style: AppTypography.caption.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// `connectivity_plus` is already a dependency (payment_screen.dart's
/// own comment on why) — `onConnectivityChanged` rather than repeatedly
/// polling `checkConnectivity()`, since this needs to react the instant
/// connectivity changes, not just when something else happens to
/// re-check it.
final _isOnlineProvider = StreamProvider.autoDispose<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});

/// The indicator itself — Volume 12: "exactly four visual states:
/// quiet/settled, a small count, actively spinning, a soft amber mark,"
/// plus [SyncStatusKind.disabled] (sync_status.dart's own doc comment
/// on why that fifth state exists). Deliberately small and quiet even
/// in its most attention-grabbing state — a soft amber dot, not a
/// banner — matching "the user should never have to think about sync
/// unless something is genuinely wrong" (Volume 12).
class _SyncStatusIndicator extends ConsumerWidget {
  const _SyncStatusIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_shellSyncStatusProvider);
    final status = statusAsync.valueOrNull;
    if (status == null) return const SizedBox.shrink();

    final (icon, color, badgeCount) = switch (status.kind) {
      SyncStatusKind.disabled => (Icons.cloud_off_outlined, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.settled => (Icons.cloud_done_outlined, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.pending => (Icons.cloud_upload_outlined, AppColors.textSecondaryOf(context), status.pendingCount),
      SyncStatusKind.syncing => (Icons.sync, AppColors.primaryOf(context), 0),
      SyncStatusKind.attentionNeeded => (Icons.warning_amber_outlined, AppColors.warningOf(context), status.attentionCount),
    };

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md, top: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.pushNamed('moreSyncDetail'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: AppIconSize.compact),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 14),
                      decoration: BoxDecoration(
                        color: status.kind == SyncStatusKind.attentionNeeded
                            ? AppColors.warningOf(context)
                            : AppColors.textSecondaryOf(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
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

/// Separate from sync_detail_screen.dart's own status provider
/// (`.autoDispose`, torn down when that screen closes) — this one backs
/// a widget that's mounted for the app's entire lifetime once signed
/// in, so it deliberately stays alive rather than repeatedly
/// resubscribing to `SyncStatusNotifier.watch()`'s underlying Drift
/// query every time a screen with `.autoDispose` semantics happened to
/// rebuild something nearby.
final _shellSyncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncStatusNotifierProvider).watch();
});

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
