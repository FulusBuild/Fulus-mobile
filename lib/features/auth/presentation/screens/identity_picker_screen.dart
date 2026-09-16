import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../shared/widgets/widgets.dart';

/// Replaces the pre-simplification SignInScreen entirely — see
/// AuthRepository.switchLocalUser's own doc comment for why a
/// username+password form no longer applies to same-device sign-in.
/// Shown by [AuthGateScreen] for [AuthGateStage.needsSignIn].
class IdentityPickerScreen extends ConsumerStatefulWidget {
  const IdentityPickerScreen({super.key});

  @override
  ConsumerState<IdentityPickerScreen> createState() => _IdentityPickerScreenState();
}

class _IdentityPickerScreenState extends ConsumerState<IdentityPickerScreen> {
  List<AuthUser>? _identities;
  AuthUser? _selected;
  final _pinController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final identities = await ref.read(authRepositoryProvider).listLocalIdentities();
    if (!mounted) return;
    setState(() {
      _identities = identities;
      if (identities.length == 1) _selected = identities.first;
    });
  }

  void _addDigit(String digit) {
    if (_submitting) return;
    setState(() {
      _pinController.text += digit;
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  void _removeDigit() {
    if (_submitting || _pinController.text.isEmpty) return;
    setState(() {
      _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
      _pinController.selection = TextSelection.collapsed(offset: _pinController.text.length);
      _error = null;
    });
  }

  Future<void> _continueAs(AuthUser identity, {String? pin}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .switchLocalUser(userId: identity.id, pin: pin);
      if (!mounted) return;
      ref.read(sessionProvider.notifier).state = user;
      context.closeScreenOr('/');
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = f.message;
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final identities = _identities;
    if (identities == null) {
      return const FulusScreen(body: Center(child: CircularProgressIndicator()));
    }
    final selected = _selected;
    if (selected == null) return _buildNameList(context, identities);
    if (!selected.hasLoginPin) return _buildContinueOnly(context, selected, showBack: identities.length > 1);
    return _buildPinEntry(context, selected, showBack: identities.length > 1);
  }

  Widget _buildNameList(BuildContext context, List<AuthUser> identities) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Who's this?",
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Choose your Fulus profile to continue.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                for (final identity in identities) ...[
                  _IdentityRow(identity: identity, onTap: () => setState(() => _selected = identity)),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContinueOnly(BuildContext context, AuthUser identity, {required bool showBack}) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBack) _buildBackButton(),
                _buildAvatar(context, identity),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Welcome back, ${identity.fullName}',
                  textAlign: TextAlign.center,
                  style: AppTypography.heading.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Ready to run your business?',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: 'Continue',
                  loading: _submitting,
                  onPressed: _submitting ? null : () => _continueAs(identity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(BuildContext context, AuthUser identity, {required bool showBack}) {
    final pinLength = _pinController.text.length;
    return FulusScreen(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showBack) Align(alignment: Alignment.centerLeft, child: _buildBackButton()),
                    _buildAvatar(context, identity),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.heading.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      identity.fullName,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _PinIndicator(length: pinLength, error: _error != null),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(color: AppColors.errorOf(context)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FulusPinKeypad(
                      onDigit: _addDigit,
                      onBackspace: _removeDigit,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: 190,
                      child: FilledButton(
                        onPressed: _submitting ? null : () => _continueAs(identity, pin: _pinController.text.trim()),
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Continue'),
                      ),
                    ),
                    if (constraints.maxHeight > 760) const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => setState(() {
        _selected = null;
        _pinController.clear();
        _error = null;
      }),
    );
  }

  Widget _buildAvatar(BuildContext context, AuthUser identity) {
    final initial = identity.fullName.trim().isEmpty ? '?' : identity.fullName.trim()[0].toUpperCase();
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.selectedTintOf(context),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppTypography.display.copyWith(
          color: AppColors.primaryOf(context),
          fontWeight: FontWeight.w800,
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

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.identity, required this.onTap});

  final AuthUser identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = identity.fullName.trim().isEmpty ? '?' : identity.fullName.trim()[0].toUpperCase();
    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.selectedTintOf(context), shape: BoxShape.circle),
            child: Text(
              initial,
              style: AppTypography.body.copyWith(
                color: AppColors.primaryOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              identity.fullName,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context), size: AppIconSize.compact),
        ],
      ),
    );
  }
}
