import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../shared/widgets/widgets.dart';

/// Replaces the pre-simplification SignInScreen entirely — see
/// AuthRepository.switchLocalUser's own doc comment for why a
/// username+password form no longer applies to same-device sign-in.
/// Shown by [AuthGateScreen] for [AuthGateStage.needsSignIn]: at least
/// one local Owner account exists on this device, but there's no active
/// session to restore.
///
/// Loads [AuthRepository.listLocalIdentities] once, then shows exactly
/// one of three things:
/// - One identity, no PIN set (the common solo-owner case — nothing was
///   ever asked to distinguish them from anyone else): a single
///   "Continue as {name}" tap, no PIN field at all.
/// - One identity, a PIN set (an owner who chose to set one on
///   themselves without ever adding a second person): straight to PIN
///   entry, same visual language as [AppLockScreen] — no name list to
///   show when there's only one name.
/// - More than one identity: a name list first (this device's "who's
///   using this" moment), then PIN entry for whichever name was tapped
///   — every identity past the first is guaranteed to have a PIN by the
///   time it exists at all (AuthRepository.createAdditionalOwner /
///   createEmployeeAccount both require the acting owner to have set
///   their own PIN first — see setOwnLoginPin's own doc comment), so
///   the PIN step is never skipped once there's a name list to show.
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
      // Nothing to pick between when there's only one — skip straight
      // to that one, same as this class's own doc comment describes.
      if (identities.length == 1) _selected = identities.first;
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
      // FIX (onboarding audit): shown both in place by AuthGateScreen
      // (needsSignIn stage — nothing to pop) and pushed from
      // RestoreProgressScreen's "Use Existing Business" (something to
      // pop). A bare `context.go('/')` left the pushed case stuck on
      // screen after a successful sign-in. closeScreenOr handles both.
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
    if (selected == null) {
      return _buildNameList(context, identities);
    }
    if (!selected.hasLoginPin) {
      return _buildContinueOnly(context, selected, showBack: identities.length > 1);
    }
    return _buildPinEntry(context, selected, showBack: identities.length > 1);
  }

  Widget _buildNameList(BuildContext context, List<AuthUser> identities) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Who's this?",
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack) _buildBackButton(),
              _buildAvatar(context, identity),
              const SizedBox(height: AppSpacing.lg),
              Text(
                identity.fullName,
                textAlign: TextAlign.center,
                style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.lg),
              FulusButton(
                label: 'Continue',
                loading: _submitting,
                onPressed: _submitting ? null : () => _continueAs(identity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(BuildContext context, AuthUser identity, {required bool showBack}) {
    return FulusScreen(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBack) _buildBackButton(),
              _buildAvatar(context, identity),
              const SizedBox(height: AppSpacing.lg),
              Text(
                identity.fullName,
                textAlign: TextAlign.center,
                style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enter your PIN to continue.',
                textAlign: TextAlign.center,
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
              FulusButton(
                label: 'Continue',
                loading: _submitting,
                onPressed: _submitting
                    ? null
                    : () => _continueAs(identity, pin: _pinController.text.trim()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() {
          _selected = null;
          _pinController.clear();
          _error = null;
        }),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, AuthUser identity) {
    // Same 88px circle-with-icon language AppLockScreen already
    // established for "who/what you're unlocking as" — an initial here
    // instead of a fixed lock glyph, since this screen (unlike
    // AppLockScreen) is specifically about WHICH identity, not just
    // whether the device is unlocked at all.
    final initial = identity.fullName.trim().isEmpty ? '?' : identity.fullName.trim()[0].toUpperCase();
    return Center(
      child: Container(
        width: 88,
        height: 88,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.selectedTintOf(context), shape: BoxShape.circle),
        child: Text(
          initial,
          style: AppTypography.display.copyWith(color: AppColors.primaryOf(context)),
        ),
      ),
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
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.selectedTintOf(context), shape: BoxShape.circle),
            child: Text(initial, style: AppTypography.body.copyWith(color: AppColors.primaryOf(context))),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              identity.fullName,
              style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context), size: AppIconSize.compact),
        ],
      ),
    );
  }
}
