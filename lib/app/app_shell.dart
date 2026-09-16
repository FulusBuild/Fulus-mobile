import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';
import '../core/theme/device_form_factor.dart';
import '../domain/entities/auth_user.dart';
import '../domain/entities/permission.dart';
import '../shared/widgets/fulus_brand_logo.dart';
import '../sync/sync_status.dart';
import 'providers.dart';

/// Global Fulus workspace shell.
///
/// Navigation is intentionally hidden until requested: swipe from the left
/// edge (or tap the menu button exposed by the drawer-aware screens) to open
/// the navigation drawer. This replaces the permanent bottom navigation bar
/// while preserving the existing StatefulShellRoute branch stacks.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({
    super.key,
    required this.navigationShell,
    required this.showMoneyTab,
  });

  final StatefulNavigationShell navigationShell;
  final bool showMoneyTab;

  static const _maxContentWidth = 840.0;

  @override
  Widget build(BuildContext context) {
    final content = isTabletWidth(context)
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: navigationShell,
            ),
          )
        : navigationShell;

    return Scaffold(
      drawer: const _FulusNavigationDrawer(),
      drawerEdgeDragWidth: 44,
      drawerEnableOpenDragGesture: true,
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                content,
                const Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(child: _SyncStatusIndicator()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FulusNavBranch {
  FulusNavBranch._();
  static const home = 0;
  static const stock = 1;
  static const sell = 2;
  static const money = 3;
  static const more = 4;
}

class _FulusNavigationDrawer extends ConsumerWidget {
  const _FulusNavigationDrawer();

  void _close(BuildContext context) => Navigator.of(context).pop();

  void _branch(BuildContext context, StatefulNavigationShell shell, int index) {
    _close(context);
    shell.goBranch(index, initialLocation: shell.currentIndex == index);
  }

  void _route(BuildContext context, String name) {
    _close(context);
    context.pushNamed(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = _shellFromContext(context);
    final user = ref.watch(sessionProvider);
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const <Permission>{};
    final isOwner = user?.role == AuthRole.owner;
    final businessNameAsync = ref.watch(_drawerBusinessNameProvider);
    final businessName = businessNameAsync.value?.trim();
    final displayBusinessName = businessName == null || businessName.isEmpty ? 'Your business' : businessName;
    final displayUserName = user?.fullName.trim().isNotEmpty == true ? user!.fullName : 'Business owner';

    final canReports = isOwner || permissions.contains(Permission.viewReports);
    final canEmployees = isOwner || permissions.contains(Permission.manageEmployees);
    final canSettings = isOwner || permissions.contains(Permission.manageSettings);

    return Drawer(
      width: isTabletWidth(context) ? 360 : MediaQuery.sizeOf(context).width * .84,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
              child: Row(
                children: [
                  const FulusBrandLogo(size: 46, padding: 9),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fulus',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Simple. Powerful. Yours.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondaryOf(context),
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close navigation',
                    onPressed: () => _close(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
                children: [
                  const _DrawerSectionLabel('RUN'),
                  _DrawerItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    selected: shell.currentIndex == FulusNavBranch.home,
                    onTap: () => _branch(context, shell, FulusNavBranch.home),
                  ),
                  _DrawerItem(
                    icon: Icons.point_of_sale_outlined,
                    label: 'Sell',
                    selected: shell.currentIndex == FulusNavBranch.sell,
                    onTap: () => _branch(context, shell, FulusNavBranch.sell),
                  ),
                  if (showMoneyTabFor(ref))
                    _DrawerItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Money',
                      selected: shell.currentIndex == FulusNavBranch.money,
                      onTap: () => _branch(context, shell, FulusNavBranch.money),
                    ),
                  const SizedBox(height: 16),
                  const _DrawerSectionLabel('MANAGE'),
                  _DrawerItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Stock',
                    selected: shell.currentIndex == FulusNavBranch.stock,
                    onTap: () => _branch(context, shell, FulusNavBranch.stock),
                  ),
                  if (showMoneyTabFor(ref))
                    _DrawerItem(
                      icon: Icons.people_outline,
                      label: 'Customers',
                      onTap: () => _route(context, 'moneyCustomers'),
                    ),
                  if (canEmployees)
                    _DrawerItem(
                      icon: Icons.badge_outlined,
                      label: 'Staff',
                      onTap: () => _route(context, 'moreEmployees'),
                    ),
                  if (canSettings)
                    _DrawerItem(
                      icon: Icons.location_on_outlined,
                      label: 'Locations',
                      onTap: () => _route(context, 'moreSettingsLocations'),
                    ),
                  const SizedBox(height: 16),
                  const _DrawerSectionLabel('UNDERSTAND'),
                  if (canReports)
                    _DrawerItem(
                      icon: Icons.bar_chart_outlined,
                      label: 'Reports',
                      onTap: () => _route(context, 'moreReports'),
                    ),
                  const SizedBox(height: 16),
                  const _DrawerSectionLabel('BUSINESS'),
                  if (canSettings)
                    _DrawerItem(
                      icon: Icons.cloud_outlined,
                      label: 'Account & Backup',
                      onTap: () => _route(context, 'moreSettingsCloud'),
                    ),
                  if (canSettings)
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => _route(context, 'moreSettings'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryOf(context).withValues(alpha: .12),
                    foregroundColor: AppColors.primaryOf(context),
                    child: Text(
                      (displayBusinessName.isNotEmpty ? displayBusinessName[0] : displayUserName[0]).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayBusinessName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          displayUserName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondaryOf(context),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  StatefulNavigationShell _shellFromContext(BuildContext context) {
    return GoRouterState.of(context).extra is StatefulNavigationShell
        ? GoRouterState.of(context).extra as StatefulNavigationShell
        : throw StateError('Fulus navigation shell is not available in drawer context');
  }

  bool showMoneyTabFor(WidgetRef ref) {
    final user = ref.read(sessionProvider);
    if (user?.role == AuthRole.owner) return true;
    final permissions = ref.read(sessionPermissionsProvider).value ?? const <Permission>{};
    return permissions.contains(Permission.viewMoney);
  }
}

final _drawerBusinessNameProvider = StreamProvider.autoDispose<String?>((ref) {
  return ref.watch(businessSettingsRepositoryProvider).watchSettings().map((profile) => profile?.businessName);
});

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: AppColors.textSecondaryOf(context),
            ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? primary.withValues(alpha: .10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: selected ? primary : AppColors.textSecondaryOf(context)),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? primary : null,
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

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(_isOnlineProvider).value ?? true;
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
                    Flexible(
                      child: Text(
                        "You're offline — your work is saved and will sync when you're back.",
                        style: AppTypography.caption.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

final _isOnlineProvider = StreamProvider.autoDispose<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});

class _SyncStatusIndicator extends ConsumerWidget {
  const _SyncStatusIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(_shellSyncStatusProvider);
    final status = statusAsync.value;
    if (status == null) return const SizedBox.shrink();

    final (icon, color, badgeCount) = switch (status.kind) {
      SyncStatusKind.disabled => (Icons.cloud_off_outlined, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.settled => (Icons.cloud_done_outlined, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.pending => (Icons.cloud_upload_outlined, AppColors.textSecondaryOf(context), status.pendingCount),
      SyncStatusKind.syncing => (Icons.sync, AppColors.primaryOf(context), 0),
      SyncStatusKind.attentionNeeded => (Icons.warning_amber_outlined, AppColors.warningOf(context), status.attentionCount),
    };

    return Semantics(
      button: true,
      label: 'Sync status',
      child: Padding(
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
      ),
    );
  }
}

final _shellSyncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncStatusNotifierProvider).watch();
});