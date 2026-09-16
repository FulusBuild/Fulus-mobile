import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/security/biometric_auth.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/auth_user.dart';
import '../../../../../domain/entities/business_settings.dart';
import '../../../../../domain/entities/permission.dart';
import '../../../../../shared/widgets/widgets.dart';

class SettingsMainScreen extends ConsumerStatefulWidget {
  const SettingsMainScreen({super.key});

  @override
  ConsumerState<SettingsMainScreen> createState() => _SettingsMainScreenState();
}

class _SettingsMainScreenState extends ConsumerState<SettingsMainScreen> {
  late Future<BusinessProfile?> _future = ref.read(businessSettingsRepositoryProvider).watchSettings().first;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final isOwner = user?.role == AuthRole.owner;
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const {};
    final canManageSettings = isOwner || permissions.contains(Permission.manageSettings);
    final canManageBackup = isOwner || permissions.contains(Permission.manageBackup);

    return FulusScreen(
      title: 'Settings',
      body: FutureBuilder<BusinessProfile?>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't load business settings.",
              onRetry: () => setState(() {
                _future = ref.read(businessSettingsRepositoryProvider).watchSettings().first;
              }),
            );
          }
          if (!snap.hasData) return const FulusLoadingIndicator();
          final profile = snap.data;
          return ListView(
            children: [
              if (canManageSettings) ...[
                FulusSectionHeader(title: 'Business'),
                if (profile != null) _BusinessInfoForm(profile: profile),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (canManageSettings || canManageBackup) ...[
                FulusSectionHeader(title: 'Devices & data'),
                if (canManageSettings) ...[
                  FulusListRow(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('Printers'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('moreSettingsPrinters'),
                  ),
                  const FulusListDivider(indented: false),
                  FulusListRow(
                    leading: const Icon(Icons.sync_outlined),
                    title: const Text('Sync'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('moreSyncDetail'),
                  ),
                  const FulusListDivider(indented: false),
                ],
                if (canManageBackup) ...[
                  FulusListRow(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Backup'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('moreSettingsBackup'),
                  ),
                  const FulusListDivider(indented: false),
                ],
                if (canManageSettings)
                  FulusListRow(
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Locations'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushNamed('moreSettingsLocations'),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (isOwner) ...[
                FulusSectionHeader(title: 'Account & Backup'),
                FulusListRow(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Account & Backup'),
                  subtitle: const Text('Back up this business and use it on other devices'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed('moreSettingsCloud'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              FulusSectionHeader(title: 'Security'),
              FulusListRow(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change approval PIN'),
                subtitle: const Text('Needed to approve discounts, refunds, and stock adjustments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openChangePinSheet(context),
              ),
              const FulusListDivider(indented: false),
              const _AppLockStatusRow(),
              const SizedBox(height: AppSpacing.lg),
              FulusSectionHeader(title: 'Account'),
              FulusListRow(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                subtitle: const Text('Your data on this device stays put — sign back in any time.'),
                onTap: () => _logout(context, ref),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showFulusConfirmDialog(
      context,
      title: 'Log out?',
      message: "You'll need your PIN to sign back in on this device.",
      confirmLabel: 'Log out',
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(authRepositoryProvider).logout();
    ref.read(sessionProvider.notifier).state = null;
  }

  void _openChangePinSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ChangePinSheet(),
    );
  }
}

class _AppLockStatusRow extends ConsumerStatefulWidget {
  const _AppLockStatusRow();

  @override
  ConsumerState<_AppLockStatusRow> createState() => _AppLockStatusRowState();
}

class _AppLockStatusRowState extends ConsumerState<_AppLockStatusRow> {
  Future<bool>? _future;

  Future<bool> _load() async {
    final config = await ref.read(appLockConfigProvider.future);
    return config.isActive();
  }

  @override
  Widget build(BuildContext context) {
    _future ??= _load();
    return FutureBuilder<bool>(
      future: _future,
      builder: (context, snap) {
        final active = snap.data ?? false;
        return FulusListRow(
          leading: const Icon(Icons.lock_outline),
          title: const Text('App Lock'),
          subtitle: Text(active ? 'On — a PIN is required to open Fulus' : 'Off'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _AppLockSheet(),
            );
            if (mounted) setState(() => _future = _load());
          },
        );
      },
    );
  }
}

class _BusinessInfoForm extends ConsumerStatefulWidget {
  const _BusinessInfoForm({required this.profile});
  final BusinessProfile profile;

  @override
  ConsumerState<_BusinessInfoForm> createState() => _BusinessInfoFormState();
}

class _BusinessInfoFormState extends ConsumerState<_BusinessInfoForm> {
  late final _nameController = TextEditingController(text: widget.profile.businessName);
  late final _addressController = TextEditingController(text: widget.profile.address ?? '');
  late final _phoneController = TextEditingController(text: widget.profile.phone ?? '');
  late final _emailController = TextEditingController(text: widget.profile.email ?? '');
  late final _tinController = TextEditingController(text: widget.profile.tin ?? '');
  late final _currencyController = TextEditingController(text: widget.profile.currencySymbol);
  late final _vatRateController = TextEditingController(text: widget.profile.vatRate.toString());
  late bool _vatEnabled = widget.profile.vatEnabled;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _tinController.dispose();
    _currencyController.dispose();
    _vatRateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(businessSettingsRepositoryProvider).updateSettings(
            businessName: _nameController.text.trim(),
            address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
            phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
            email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
            tin: _tinController.text.trim().isEmpty ? null : _tinController.text.trim(),
            vatEnabled: _vatEnabled,
            vatRate: double.tryParse(_vatRateController.text.trim()) ?? widget.profile.vatRate,
            currencySymbol: _currencyController.text.trim().isEmpty ? widget.profile.currencySymbol : _currencyController.text.trim(),
            receiptFooter: widget.profile.receiptFooter,
          );
      if (mounted) {
        showFulusSnackbar(context, message: 'Saved.');
        setState(() => _saving = false);
      }
    } on Failure catch (f) {
      if (mounted) setState(() {
        _saving = false;
        _error = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => FulusCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
              const SizedBox(height: AppSpacing.sm),
            ],
            FulusTextField(label: 'Business name', controller: _nameController),
            const SizedBox(height: AppSpacing.sm),