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
                FulusSectionHeader(title: 'Cloud'),
                FulusListRow(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Fulus Cloud'),
                  subtitle: const Text('Connect this business for server-authoritative sync'),
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
            FulusTextField(label: 'Address', controller: _addressController),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Phone', controller: _phoneController, keyboardType: TextInputType.phone),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Email', controller: _emailController, keyboardType: TextInputType.emailAddress),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Tax ID (TIN)', controller: _tinController),
            const SizedBox(height: AppSpacing.sm),
            FulusTextField(label: 'Currency symbol', controller: _currencyController),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _vatEnabled,
              onChanged: (v) => setState(() => _vatEnabled = v),
              title: Text('VAT enabled', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Businesses under ₦100m annual turnover are exempt from VAT collection under the Nigeria Tax Act 2025. Confirm your own registration status before enabling this.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ),
            if (_vatEnabled) ...[
              const SizedBox(height: AppSpacing.sm),
              FulusTextField(
                label: 'VAT rate (%)',
                controller: _vatRateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FulusButton(label: 'Save', loading: _saving, onPressed: _saving ? null : _save),
            ),
          ],
        ),
      );
}

class _ChangePinSheet extends ConsumerStatefulWidget {
  const _ChangePinSheet();

  @override
  ConsumerState<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<_ChangePinSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Use at least 4 digits.');
      return;
    }
    if (pin != _confirmController.text.trim()) {
      setState(() => _error = "PINs don't match.");
      return;
    }
    final userId = ref.read(sessionProvider)?.id;
    if (userId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(approvalPinRepositoryProvider).setOwnApprovalPin(userId: userId, pin: pin);
      if (mounted) {
        Navigator.of(context).pop();
        showFulusSnackbar(context, message: 'Approval PIN updated.');
      }
    } on Failure catch (f) {
      if (mounted) setState(() {
        _saving = false;
        _error = f.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = "Couldn't reach the server — this needs a connection the first time.";
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change approval PIN', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: AppSpacing.xs),
              Text('Needs a connection this one time, to sync to the server.', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ...[
                Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                const SizedBox(height: AppSpacing.sm),
              ],
              FulusTextField(label: 'New PIN', controller: _pinController, obscureText: true, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.sm),
              FulusTextField(label: 'Confirm PIN', controller: _confirmController, obscureText: true, keyboardType: TextInputType.number),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(width: double.infinity, child: FulusButton(label: 'Save', loading: _saving, onPressed: _saving ? null : _save)),
            ],
          ),
        ),
      );
}

class _AppLockSheet extends ConsumerStatefulWidget {
  const _AppLockSheet();

  @override
  ConsumerState<_AppLockSheet> createState() => _AppLockSheetState();
}

class _AppLockSheetState extends ConsumerState<_AppLockSheet> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _biometricAuth = BiometricAuth();
  bool _active = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _loading = true;
  bool _saving = false;
  bool _biometricSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await ref.read(appLockConfigProvider.future);
      final active = await config.isActive();
      final enabled = active && await config.isBiometricEnabled();
      final available = active && await _biometricAuth.isAvailable();
      if (mounted) setState(() {
        _active = active;
        _biometricEnabled = enabled;
        _biometricAvailable = available;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Couldn\'t load App Lock settings.';
      });
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _turnOff() async {
    setState(() => _saving = true);
    final config = await ref.read(appLockConfigProvider.future);
    await config.removePin();
    if (mounted) {
      Navigator.of(context).pop();
      showFulusSnackbar(context, message: 'App Lock turned off.');
    }
  }

  Future<void> _setPin() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'Use at least 4 digits.');
      return;
    }
    if (pin != _confirmController.text.trim()) {
      setState(() => _error = "PINs don't match.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final config = await ref.read(appLockConfigProvider.future);
    await config.setPin(pin);
    if (mounted) {
      Navigator.of(context).pop();
      showFulusSnackbar(context, message: 'App Lock turned on.');
    }
  }

  Future<void> _setBiometric(bool value) async {
    if (_biometricSaving) return;
    final config = await ref.read(appLockConfigProvider.future);

    if (!value) {
      setState(() => _biometricSaving = true);
      try {
        await config.setBiometricEnabled(false);
        if (mounted) setState(() {
          _biometricEnabled = false;
          _biometricSaving = false;
        });
      } catch (_) {
        if (mounted) setState(() => _biometricSaving = false);
      }
      return;
    }

    if (!_biometricAvailable) {
      if (mounted) showFulusSnackbar(context, message: 'No fingerprint or face unlock is available on this device.');
      return;
    }

    setState(() {
      _biometricSaving = true;
      _error = null;
    });
    try {
      final authenticated = await _biometricAuth.authenticate();
      if (!authenticated) {
        if (mounted) setState(() => _biometricSaving = false);
        return;
      }
      await config.setBiometricEnabled(true);
      if (mounted) {
        setState(() {
          _biometricEnabled = true;
          _biometricSaving = false;
        });
        showFulusSnackbar(context, message: 'Biometric unlock is on.');
      }
    } catch (_) {
      if (mounted) setState(() {
        _biometricSaving = false;
        _error = 'Couldn\'t enable biometric unlock. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App Lock', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'When on, Fulus asks for this PIN every time it\'s opened or resumed from the background — separate from your approval PIN.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_active) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _biometricEnabled,
                    onChanged: _biometricSaving ? null : _setBiometric,
                    title: Text('Use biometric unlock', style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
                    subtitle: Text(
                      _biometricAvailable ? 'Use your phone\'s fingerprint or face to unlock Fulus.' : 'No biometric method is available on this device.',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(
                      label: 'Turn off App Lock',
                      variant: FulusButtonVariant.secondary,
                      loading: _saving,
                      onPressed: _saving || _biometricSaving ? null : _turnOff,
                    ),
                  ),
                ] else ...[
                  if (_error != null) ...[
                    Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  FulusTextField(label: 'New PIN', controller: _pinController, obscureText: true, keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.sm),
                  FulusTextField(label: 'Confirm PIN', controller: _confirmController, obscureText: true, keyboardType: TextInputType.number),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(width: double.infinity, child: FulusButton(label: 'Turn on App Lock', loading: _saving, onPressed: _saving ? null : _setPin)),
                ],
              ],
            ),
    );
  }
}
