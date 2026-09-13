import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/security/biometric_auth.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Full-screen app lock. PIN remains the offline fallback; device biometrics
/// are a convenience layer backed entirely by Android/iOS system auth.
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
    final available = await _biometricAuth.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available && !_biometricAttempted) {
      _biometricAttempted = true;
      await _unlockWithBiometric();
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final authenticated = await _biometricAuth.authenticate();
    if (!mounted) return;
    if (authenticated) {
      widget.onUnlocked();
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _unlock() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    final config = await ref.read(appLockConfigProvider.future);
    final correct = await config.verifyPin(pin);
    if (!mounted) return;
    if (correct) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = 'Incorrect PIN.';
      _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.backgroundOf(context),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.selectedTintOf(context),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _biometricAvailable ? Icons.fingerprint_rounded : Icons.lock_outline_rounded,
                      size: 48,
                      color: AppColors.primaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Welcome back',
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _biometricAvailable
                        ? 'Unlock Fulus with your fingerprint or PIN.'
                        : 'Enter your PIN to continue.',
                    style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_biometricAvailable) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FulusButton(
                        label: 'Use fingerprint',
                        icon: Icons.fingerprint_rounded,
                        loading: _checking,
                        onPressed: _checking ? null : _unlockWithBiometric,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          child: Text(
                            'or use PIN',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  FulusTextField(
                    label: 'PIN',
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    errorText: _error,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    suffixIcon: Semantics(
                      label: 'Clear',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.backspace_outlined),
                        onPressed: _pinController.clear,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(
                      label: 'Unlock',
                      loading: _checking && !_biometricAvailable,
                      onPressed: _checking ? null : _unlock,
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
