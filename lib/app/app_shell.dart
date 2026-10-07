import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';
import '../core/ux/consumer_polish.dart';
import '../domain/entities/auth_user.dart';
import '../domain/entities/permission.dart';
import '../core/theme/device_form_factor.dart';
import '../core/theme/fulus_icons.dart';
import '../sync/sync_status.dart';
import 'providers.dart';

/// Global Fulus workspace shell.
/// Primary navigation is persistent and uses the mockup-aligned bottom bar.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({super.key, required this.navigationShell, required this.showMoneyTab});

  final StatefulNavigationShell navigationShell;
  final bool showMoneyTab;

  static const _maxContentWidth = 1120.0;
  @override
  Widget build(BuildContext context) {
    final content = isTabletWidth(context)
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: ClipRect(child: navigationShell),
            ),
          )
        : navigationShell;

    return Scaffold(
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                content,
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _FulusBottomNavigationBar(
        navigationShell: navigationShell,
        showMoneyTab: showMoneyTab,
      ),
    );
  }
}

class _FulusBottomNavigationBar extends StatelessWidget {
  const _FulusBottomNavigationBar({
    required this.navigationShell,
    required this.showMoneyTab,
  });

  final StatefulNavigationShell navigationShell;
  final bool showMoneyTab;

  void _select(int branch) {
    navigationShell.goBranch(
      branch,
      initialLocation: navigationShell.currentIndex == branch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <(int, IconData, String)>[
      (FulusNavBranch.home, FulusIcons.home, 'Home'),
      (FulusNavBranch.sell, FulusIcons.sell, 'Sell'),
      (FulusNavBranch.stock, FulusIcons.stock, 'Stock'),
      if (showMoneyTab) (FulusNavBranch.money, FulusIcons.navMoney, 'Money'),
      (FulusNavBranch.more, FulusIcons.navMore, 'More'),
    ];

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // Scaffold gives bottomNavigationBar a loose vertical constraint. Without
    // an explicit height, the custom Row can grow to the available viewport on
    // some Android devices, effectively covering the whole screen. Keep the
    // Fulus bar compact while adding the system navigation inset separately.
    const barContentHeight = 64.0;
    return SizedBox(
      height: barContentHeight + bottomInset,
      child: Material(
        color: AppColors.surfaceOf(context),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.borderOf(context).withValues(alpha: .7)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.xs,
            0,
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                for (final item in items)
                  Expanded(
                    child: _FulusBottomNavigationItem(
                      icon: item.$2,
                      label: item.$3,
                      selected: navigationShell.currentIndex == item.$1,
                      onTap: () => _select(item.$1),
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

class _FulusBottomNavigationItem extends StatelessWidget {
  const _FulusBottomNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final foreground = selected ? primary : AppColors.textSecondaryOf(context);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
              child: AnimatedContainer(
                // Workspace selection is immediate. A moving selection pill makes the
                // previous and destination workspace visible together in slow motion.
                duration: Duration.zero,
                curve: AppMotion.curveStandard,
                decoration: const BoxDecoration(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconTheme(
                      data: IconThemeData(
                        color: foreground,
                        fill: selected ? 1 : 0,
                        weight: 300,
                        grade: 0,
                        opticalSize: 24,
                      ),
                      child: Icon(icon, size: AppIconSize.compact),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: AppTypography.label.copyWith(
                          color: foreground,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FulusNavBranch {
  FulusNavBranch._();
  static const home = 0;
  // StatefulShellRoute branches are declared as home, stock, sell, money, more.
  static const sell = 2;
  static const stock = 1;
  static const money = 3;
  static const more = 4;
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(_isOnlineProvider).value ?? true;
    return AnimatedSize(
      duration: fulusMotionDuration(context, AppMotion.standard),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(FulusIcons.cloudOff, color: Colors.white, size: AppIconSize.dense),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        "You're offline — your work is saved and will sync when you're back.",
                        maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 3 : 2,
                        style: AppTypography.caption.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

final _isOnlineProvider = StreamProvider.autoDispose<bool>((ref) => Connectivity().onConnectivityChanged.map((results) => results.any((r) => r != ConnectivityResult.none)));

class FulusSyncStatusIndicator extends ConsumerWidget {
  const FulusSyncStatusIndicator({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawStatus = ref.watch(_shellSyncStatusProvider).value;
    final connection = ref.watch(fulusConnectionStateProvider);
    final user = ref.watch(sessionProvider);
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const {};
    final canOpenSync =
        user?.role == AuthRole.owner || permissions.contains(Permission.manageSettings);
    if (rawStatus == null) return const SizedBox.shrink();
    final status = rawStatus.kind == SyncStatusKind.disabled || connection.isSyncReady
        ? rawStatus
        : const SyncStatus.cloudUnavailable();
    final (icon, color, badgeCount) = switch (status.kind) {
      SyncStatusKind.disabled => (FulusIcons.cloudOff, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.cloudUnavailable => (FulusIcons.cloudOff, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.settled => (FulusIcons.cloudDone, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.pending => (FulusIcons.cloudUpload, AppColors.textSecondaryOf(context), status.pendingCount),
      SyncStatusKind.syncing => (FulusIcons.sync, AppColors.primaryOf(context), 0),
      SyncStatusKind.attentionNeeded => (FulusIcons.warning, AppColors.warningOf(context), status.attentionCount),
    };
    return Semantics(
      button: canOpenSync,
      label: canOpenSync ? 'Sync status' : 'Sync status unavailable',
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md, top: AppSpacing.xs),
        child: Material(
          color: AppColors.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: .7)),
          ),
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: .10),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: canOpenSync ? () => context.pushNamed('moreSyncDetail') : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Stack(clipBehavior: Clip.none, children: [
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
                        style: TextStyle(
                          color: status.kind == SyncStatusKind.attentionNeeded
                              ? AppColors.warningOnOf(context)
                              : AppColors.onColor(AppColors.textSecondaryOf(context)),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _shellSyncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.watch(syncStatusNotifierProvider).watch());

