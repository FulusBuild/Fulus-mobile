import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/design_tokens.dart';
import '../core/theme/device_form_factor.dart';
import '../core/theme/fulus_icons.dart';
import '../domain/entities/auth_user.dart';
import '../domain/entities/permission.dart';
import '../shared/widgets/fulus_brand_logo.dart';
import '../sync/sync_status.dart';
import 'providers.dart';

/// Global Fulus workspace shell.
/// Navigation stays hidden until requested and works equally well on phones
/// and tablets. Feature screens remain responsible for their own content.
class FulusAppShell extends StatelessWidget {
  const FulusAppShell({super.key, required this.navigationShell, required this.showMoneyTab});

  final StatefulNavigationShell navigationShell;
  final bool showMoneyTab;

  static const _maxContentWidth = 1120.0;
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  static void openDrawer() => scaffoldKey.currentState?.openDrawer();

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
      key: scaffoldKey,
      drawer: _FulusNavigationDrawer(shell: navigationShell, showMoneyTab: showMoneyTab),
      drawerEdgeDragWidth: 52,
      drawerEnableOpenDragGesture: true,
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                content,
                const Positioned(top: 0, right: 0, child: SafeArea(child: _SyncStatusIndicator())),
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
  const _FulusNavigationDrawer({required this.shell, required this.showMoneyTab});
  final StatefulNavigationShell shell;
  final bool showMoneyTab;

  void _close(BuildContext context) => Navigator.of(context).pop();
  void _branch(BuildContext context, int index) {
    _close(context);
    shell.goBranch(index, initialLocation: shell.currentIndex == index);
  }
  void _route(BuildContext context, String name) {
    _close(context);
    context.pushNamed(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const <Permission>{};
    final isOwner = user?.role == AuthRole.owner;
    final businessName = ref.watch(_drawerBusinessNameProvider).value?.trim();
    final displayBusinessName = businessName == null || businessName.isEmpty ? 'Your business' : businessName;
    final displayUserName = user?.fullName.trim().isNotEmpty == true ? user!.fullName : 'Business owner';
    final canReports = isOwner || permissions.contains(Permission.viewReports);
    final canEmployees = isOwner || permissions.contains(Permission.manageEmployees);
    final canSettings = isOwner || permissions.contains(Permission.manageSettings);

    return Drawer(
      width: isTabletWidth(context) ? 360 : MediaQuery.sizeOf(context).width * .86,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.md, AppSpacing.md),
              child: Row(
                children: [
                  const FulusBrandLogo(size: 48, padding: 9),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fulus', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Your business, in your hands', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedOf(context))),
                      ],
                    ),
                  ),
                  FulusIconButton(
                    icon: FulusIcons.close,
                    tooltip: 'Close navigation',
                    onPressed: () => _close(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderOf(context).withValues(alpha: .6)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.sm, AppSpacing.lg),
                children: [
                  const _DrawerSectionLabel('RUN'),
                  _DrawerItem(icon: FulusIcons.home, label: 'Home', selected: shell.currentIndex == FulusNavBranch.home, onTap: () => _branch(context, FulusNavBranch.home)),
                  _DrawerItem(icon: FulusIcons.sell, label: 'Sell', selected: shell.currentIndex == FulusNavBranch.sell, onTap: () => _branch(context, FulusNavBranch.sell)),
                  if (showMoneyTab) _DrawerItem(icon: FulusIcons.money, label: 'Money', selected: shell.currentIndex == FulusNavBranch.money, onTap: () => _branch(context, FulusNavBranch.money)),
                  const SizedBox(height: AppSpacing.xl),
                  const _DrawerSectionLabel('MANAGE'),
                  _DrawerItem(icon: FulusIcons.stock, label: 'Stock', selected: shell.currentIndex == FulusNavBranch.stock, onTap: () => _branch(context, FulusNavBranch.stock)),
                  if (showMoneyTab) _DrawerItem(icon: FulusIcons.customers, label: 'Customers', onTap: () => _route(context, 'moneyCustomers')),
                  if (canEmployees) _DrawerItem(icon: FulusIcons.staff, label: 'Staff', onTap: () => _route(context, 'moreEmployees')),
                  if (canSettings) _DrawerItem(icon: FulusIcons.locations, label: 'Locations', onTap: () => _route(context, 'moreSettingsLocations')),
                  const SizedBox(height: AppSpacing.xl),
                  const _DrawerSectionLabel('UNDERSTAND'),
                  if (canReports) _DrawerItem(icon: FulusIcons.reports, label: 'Reports', onTap: () => _route(context, 'moreReports')),
                  const SizedBox(height: AppSpacing.xl),
                  const _DrawerSectionLabel('BUSINESS'),
                  if (canSettings) _DrawerItem(icon: FulusIcons.cloud, label: 'Account & Backup', onTap: () => _route(context, 'moreSettingsCloud')),
                  if (canSettings) _DrawerItem(icon: FulusIcons.settings, label: 'Settings', onTap: () => _route(context, 'moreSettings')),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.borderOf(context).withValues(alpha: .6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: AppColors.primaryOf(context).withValues(alpha: .10),
                    foregroundColor: AppColors.primaryOf(context),
                    child: Text((displayBusinessName.isNotEmpty ? displayBusinessName[0] : displayUserName[0]).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayBusinessName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(displayUserName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedOf(context))),
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
}

final _drawerBusinessNameProvider = StreamProvider.autoDispose<String?>((ref) => ref.watch(businessSettingsRepositoryProvider).watchSettings().map((profile) => profile?.businessName));

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.mutedOf(context))),
      );
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final foreground = selected ? primary : AppColors.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? primary.withValues(alpha: .10) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(icon, size: AppIconSize.base, color: foreground),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? primary : null))),
                  if (selected) Icon(FulusIcons.chevronRight, size: AppIconSize.compact, color: primary),
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
      duration: AppMotion.standard,
      child: isOnline
          ? const SizedBox(width: double.infinity)
          : SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                color: AppColors.textSecondaryOf(context),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.md),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(FulusIcons.cloudOff, color: Colors.white, size: AppIconSize.dense),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(child: Text("You're offline — your work is saved and will sync when you're back.", style: AppTypography.caption.copyWith(color: Colors.white), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
    );
  }
}

final _isOnlineProvider = StreamProvider.autoDispose<bool>((ref) => Connectivity().onConnectivityChanged.map((results) => results.any((r) => r != ConnectivityResult.none)));

class _SyncStatusIndicator extends ConsumerWidget {
  const _SyncStatusIndicator();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_shellSyncStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final (icon, color, badgeCount) = switch (status.kind) {
      SyncStatusKind.disabled => (FulusIcons.cloudOff, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.settled => (FulusIcons.cloudDone, AppColors.textSecondaryOf(context), 0),
      SyncStatusKind.pending => (FulusIcons.cloudUpload, AppColors.textSecondaryOf(context), status.pendingCount),
      SyncStatusKind.syncing => (FulusIcons.sync, AppColors.primaryOf(context), 0),
      SyncStatusKind.attentionNeeded => (FulusIcons.warning, AppColors.warningOf(context), status.attentionCount),
    };
    return Semantics(
      button: true,
      label: 'Sync status',
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
            onTap: () => context.pushNamed('moreSyncDetail'),
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
                      decoration: BoxDecoration(color: status.kind == SyncStatusKind.attentionNeeded ? AppColors.warningOf(context) : AppColors.textSecondaryOf(context), borderRadius: BorderRadius.circular(8)),
                      child: Text('$badgeCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

final _shellSyncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.watch(syncStatusNotifierProvider).watch());
