import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../domain/entities/business_settings.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Gap fix — the More screen's own header comment called this out by
/// name: "settings beyond Backup, and a proper Volume 9-11 layout, are
/// still genuinely undone work." This is that work: Business info
/// (BusinessSettingsRepository.updateSettings already existed with no
/// caller — see that repository's own header comment), and a real home
/// for Printers, Sync & Backup, Locations, and Security, replacing the
/// literal on-screen "Not yet built" text.
///
/// Language/Theme/Accessibility (also named in Volume 11) is
/// deliberately not attempted here — MaterialApp.router's themeMode is
/// hardcoded to ThemeMode.system with its own comment explaining no
/// provider exists for it yet, and building one is a separate, real
/// feature, not a Settings-hub wiring task like everything else on this
/// screen.
class SettingsMainScreen extends ConsumerStatefulWidget {
  const SettingsMainScreen({super.key});

  @override
  ConsumerState<SettingsMainScreen> createState() => _SettingsMainScreenState();
}

class _SettingsMainScreenState extends ConsumerState<SettingsMainScreen> {
  late Future<BusinessProfile?> _future = ref.read(businessSettingsRepositoryProvider).watchSettings().first;

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Settings',
      body: FutureBuilder<BusinessProfile?>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return FulusErrorState(
              message: "Couldn't load business settings.",
              onRetry: () => setState(() => _future =
                  ref.read(businessSettingsRepositoryProvider).watchSettings().first),
            );
          }
          if (!snap.hasData) {
            return const FulusLoadingIndicator();
          }
          final profile = snap.data;
          return ListView(
            children: [
              FulusSectionHeader(title: 'Business'),
              if (profile != null) _BusinessInfoForm(profile: profile),
              const SizedBox(height: AppSpacing.lg),
              FulusSectionHeader(title: 'Devices & data'),
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
              FulusListRow(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Backup'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed('moreSettingsBackup'),
              ),
              const FulusListDivider(indented: false),
              FulusListRow(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Locations'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed('moreSettingsLocations'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FulusSectionHeader(title: 'Security'),
              FulusListRow(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change approval PIN'),
                subtitle: const Text('Needed to approve discounts, refunds, and stock adjustments'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openChangePinSheet(context),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  void _openChangePinSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ChangePinSheet(),
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
  Widget build(BuildContext context) {
    return FulusCard(
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
      // setOwnApprovalPin requires connectivity the first time it syncs
      // (this screen's own header comment on why) — a plain connection
      // failure isn't necessarily a Failure subtype.
      if (mounted) setState(() {
        _saving = false;
        _error = "Couldn't reach the server — this needs a connection the first time.";
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change approval PIN', style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Needs a connection this one time, to sync to the server.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            Text(_error!, style: AppTypography.body.copyWith(color: AppColors.errorOf(context))),
            const SizedBox(height: AppSpacing.sm),
          ],
          FulusTextField(
            label: 'New PIN',
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusTextField(
            label: 'Confirm PIN',
            controller: _confirmController,
            obscureText: true,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FulusButton(label: 'Save', loading: _saving, onPressed: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}
