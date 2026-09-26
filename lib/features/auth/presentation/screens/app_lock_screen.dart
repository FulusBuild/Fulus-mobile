import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/security/biometric_auth.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/fulus_button.dart';
import '../../../../shared/widgets/fulus_brand_logo.dart';
import '../../../../shared/widgets/pin_keypad.dart';

/// Full-screen app lock. PIN remains the reliable fallback; biometrics are
/// used only when explicitly enabled in Settings.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pinController = TextEditingController();
  final _biometricAuth = BiometricAuth();
  String? _error;
  bool _checking = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareBiometric());
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometric() async {
    try {
      final config = await ref.read(appLockConfigProvider.future);
      final enabled = await config.isBiometricEnabled();
      final available = enabled && await _biometricAuth.isAvailable();
      if (!mounted) return;
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = available;
      });
      if (available && !_biometricAttempted) {
        _biometricAttempted = true;
        await _unlockWithBiometric();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricEnabled = false;
        _biometricAvailable = false;
      });
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final authenticated = await _biometricAuth.authenticate();
      if (!mounted) return;
      if (authenticated) {
        widget.onUnlocked();
        return;
      }
    } catch (_) {
      // PIN remains available if the device biometric flow fails.
    }
    if (mounted) setState(() => _checking = false);
  }

  void _addDigit(String digit) {
    if (_checking) return;
    setState(() {
      _pinController.text += digit;
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  void _removeDigit() {
    if (_checking || _pinController.text.isEmpty) return;
    setState(() {
      _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  Future<void> _unlock() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4 || _checking) {
      if (pin.isNotEmpty && pin.length < 4) setState(() => _error = 'Use at least 4 digits.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final config = await ref.read(appLockConfigProvider.future);
      final correct = await config.verifyPin(pin).timeout(const Duration(seconds: 30));
      if (!mounted) return;

      if (!correct) {
        setState(() {
          _checking = false;
          _error = 'Incorrect PIN. Try again.';
          _pinController.clear();
        });
        return;
      }

      widget.onUnlocked();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'PIN check took too long. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'PIN verification is temporarily unavailable. Please try again.';
      });
    }
  }

  void _showForgotPinInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surfaceOf(context),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 8, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forgot your PIN?', style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(sheetContext))),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your app PIN is stored securely on this device. If biometric unlock is enabled, you can use it instead. Otherwise, the PIN must be changed from Fulus Settings after the app is unlocked.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(sheetContext)),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FulusButton(
                label: 'Got it',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final biometricReady = _biometricEnabled && _biometricAvailable;
    final pinLength = _pinController.text.length;

    return Material(
      color: AppColors.backgroundOf(context),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FulusBrandLogo(size: 58, padding: 10),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Enter your PIN',
                        style: AppTypography.heading.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        biometricReady ? 'Use your PIN or device biometrics to unlock Fulus.' : 'Keep your business secure.',
                        style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _PinIndicator(length: pinLength, error: _error != null),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _error!,
                          style: AppTypography.caption.copyWith(color: AppColors.errorOf(context)),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      FulusPinKeypad(
                        onDigit: _addDigit,
                        onBackspace: _removeDigit,
                        enabled: !_checking,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (biometricReady)
                        _BiometricAction(
                          loading: _checking,
                          onTap: _checking ? null : _unlockWithBiometric,
                        )
                      else
                        FulusButton(
                          label: 'Forgot PIN?',
                          variant: FulusButtonVariant.text,
                          onPressed: _checking ? null : _showForgotPinInfo,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: 180,
                        child: FulusButton(
                          label: 'Unlock',
                          loading: _checking,
                          onPressed: _checking ? null : _unlock,
                        ),
                      ),
                      if (constraints.maxHeight > 760) const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PinIndicator extends StatelessWidget {
  const _PinIndicator({required this.length, required this.error});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final visibleCount = length.clamp(4, 8);
    final primary = AppColors.primaryOf(context);
    final border = error ? AppColors.errorOf(context) : AppColors.borderOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleCount; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? primary : Colors.transparent,
              border: Border.all(color: i < length ? primary : border, width: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _BiometricAction extends StatelessWidget {
  const _BiometricAction({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return TextButton.icon(
      onPressed: onTap,
      icon: loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
            )
          : Icon(Icons.fingerprint_rounded, size: 21, color: primary),
      label: Text('Use biometrics', style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
    );
  }
}
