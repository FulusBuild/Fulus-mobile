import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';

/// Returning-user sign-in — username + password, verified against the
/// local Users table via [AuthRepository.login]. Serves Owner and
/// Employee logins identically; role isn't known until after the
/// lookup, so there's no branch for it here — see [AuthGateScreen]'s
/// own doc comment for the fuller reasoning on why this is the only
/// sign-in path this phase builds.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter your username and password.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final user = await ref.read(authRepositoryProvider).login(
            username: username,
            password: password,
          );
      if (!mounted) return;
      // The reactive "revisit" AuthRepository's own doc comment named —
      // see providers.dart's sessionProvider. This is the write half of
      // that provider's contract; AuthRepositoryImpl.login already
      // succeeded and persisted the session by this point, this line
      // only makes the UI aware of it.
      ref.read(sessionProvider.notifier).state = user;
    } on Failure catch (f) {
      if (!mounted) return;
      // Every Failure variant's .message is documented as "safe to show
      // directly" (failure.dart) — no need to branch on which variant
      // this is; AuthFailure.accountLocked's exact unlock time isn't
      // reachable from here even if this screen wanted to format it
      // itself (that field lives on a private subtype for a reason —
      // see failure.dart), which is fine, since .message already says
      // what a signed-in-out user needs to hear.
      setState(() => _errorMessage = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Welcome back',
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Sign in to continue.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_errorMessage != null) ...[
                  AuthErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                FulusTextField(
                  label: 'Username',
                  controller: _usernameController,
                  onChanged: (_) {
                    if (_errorMessage != null) setState(() => _errorMessage = null);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                FulusTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: (_) {
                    if (_errorMessage != null) setState(() => _errorMessage = null);
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: 'Sign in',
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
