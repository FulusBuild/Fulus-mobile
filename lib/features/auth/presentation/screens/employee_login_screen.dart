import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Employee account authentication after the invitation has already been
/// claimed. The invitation is never part of this flow.
class EmployeeLoginScreen extends ConsumerStatefulWidget {
  const EmployeeLoginScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends ConsumerState<EmployeeLoginScreen> {
  String _loginErrorMessage(Failure failure) {
    if (failure is BusinessRuleFailure &&
        (failure.code?.startsWith('SYNC_') ?? false)) {
      return 'We couldn’t finish signing you in. Please try again.';
    }
    if (failure is NetworkFailure) {
      return 'We couldn’t connect right now. Please try again.';
    }
    return failure.message;
  }
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');
  final _passwordController = TextEditingController();
  bool _busy = false;
  String _status = '';
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your Fulus email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Signing you in…';
    });

    final connection = ref.read(fulusConnectionStateProvider);
    // Arm the cloud lifecycle fence before authentication changes the active
    // cloud session. Otherwise SyncTriggers can observe the newly authenticated
    // session and start bootstrap/restore before employee provisioning owns the
    // session lifecycle.
    connection.beginCloudOnboarding();
    try {
      await ref.read(authApiProvider).connectServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );

      connection.markSessionAuthenticated();
      await connection.refresh();

      final active = connection.membershipContext?.memberships
              .where((membership) => membership.status == 'active')
              .toList(growable: false) ??
          const [];
      if (active.length != 1) {
        throw const BusinessRuleFailure(
          'This employee account does not have one active Fulus business to restore.',
        );
      }

      await connection.selectBusiness(active.single.businessId);
      final claim =
          await ref.read(fulusStaffAccessApiProvider).getMyAccess(
                businessId: active.single.businessId,
              );
      if (claim.roleName == 'owner' || claim.roleName == 'admin') {
        throw const BusinessRuleFailure(
          'This is an owner or admin account. Use the regular Fulus sign-in.',
        );
      }

      setState(() => _status = 'Restoring your business…');
      final employee =
          await ref.read(employeeCloudSessionCoordinatorProvider).establish(
                claim: claim,
                onProgress: (status) {
                  if (mounted) setState(() => _status = status);
                },
              );

      ref.read(sessionProvider.notifier).state = employee;
      if (!mounted) return;
      context.go('/');
    } on Failure catch (failure) {
      await _clearFailedCloudSession();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _loginErrorMessage(failure);
          _status = '';
        });
      }
    } catch (error) {
      await _clearFailedCloudSession();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'We couldn’t finish signing you in. Please try again.';
          _status = '';
        });
      }
    } finally {
      // EmployeeCloudSessionCoordinator.establish() owns a nested fence during
      // restore. The outer reference covers authentication and membership
      // resolution and is released only after the whole handoff finishes.
      connection.endCloudOnboarding();
    }
  }

  Future<void> _clearFailedCloudSession() async {
    try {
      await ref.read(apiClientProvider).clearActiveCloudSession();
      ref.read(fulusConnectionStateProvider).disconnect();
      await ref.read(syncServiceProvider).disable();
      await ref.read(authRepositoryProvider).logout();
      ref.read(sessionProvider.notifier).state = null;
    } catch (_) {
      // Cleanup is best-effort; the visible login error remains actionable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sign in',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.login_rounded,
                    size: 64,
                    color: AppColors.primaryOf(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      color: AppColors.primaryOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in with your Fulus email and password.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FulusTextField(
                    label: 'Email',
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FulusTextField(
                    label: 'Fulus password',
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FulusButton(
                    label: _busy ? 'Signing in…' : 'Sign in',
                    loading: _busy,
                    onPressed: _busy ? null : _login,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Your App Lock or approval PIN is separate from your Fulus password.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FulusCard(
                      child: Text(
                        _error!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.errorOf(context),
                        ),
                      ),
                    ),
                  ],
                  if (_busy && _status.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
