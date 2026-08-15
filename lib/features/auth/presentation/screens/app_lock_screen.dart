import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Volume 11 / visual bible Batch 6's "App Lock Unlock" screen. Shown
/// by [AppLockGate] as a full-screen overlay above everything else —
/// not a routed screen, since it needs to appear regardless of
/// wherever go_router's own stack currently is, including mid-flow in
/// something like Checkout.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.selectedTintOf(context), shape: BoxShape.circle),
                  child: Icon(Icons.lock_outline, size: AppIconSize.emphasis, color: AppColors.primaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Fulus is locked',
                  style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Enter your PIN to continue.',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.lg),
                FulusTextField(
                  label: 'PIN',
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  errorText: _error,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FulusButton(label: 'Unlock', loading: _checking, onPressed: _checking ? null : _unlock),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
