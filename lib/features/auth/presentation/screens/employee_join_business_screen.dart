import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../data/remote/fulus_staff_access_api.dart';
import '../../../../shared/widgets/widgets.dart';

/// First-device employee onboarding.
///
/// The invitation is the source of truth for first-time business access.
/// After the account is created, every later sign-in uses the Fulus email and
/// password; the invitation is never requested again.
class EmployeeJoinBusinessScreen extends ConsumerStatefulWidget {
  const EmployeeJoinBusinessScreen({super.key});

  @override
  ConsumerState<EmployeeJoinBusinessScreen> createState() =>
      _EmployeeJoinBusinessScreenState();
}

class _EmployeeJoinBusinessScreenState
    extends ConsumerState<EmployeeJoinBusinessScreen> {
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();

  StaffInvitePreview? _preview;
  bool _busy = false;
  String? _error;
  String _status = '';

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _continueFromInvite() async {
    if (_busy) return;
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste the invitation code you received.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Checking your invitation…';
    });

    try {
      final preview =
          await ref.read(fulusStaffAccessApiProvider).inspectInvite(token);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
        _status = '';
      });
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _joinErrorMessage(failure);
          _status = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'We couldn’t finish joining your business. Please try again.';
          _status = '';
        });
      }
    }
  }

  Future<void> _join() async {
    if (_busy || _preview == null) return;
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _error = 'Use a password of at least 8 characters.');
      return;
    }

    final preview = _preview!;
    final token = _tokenController.text.trim();

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Creating your Fulus login…';
    });

    try {
      try {
        await ref.read(fulusStaffAccessApiProvider).prepareInvitedAccount(
              token: token,
              password: password,
            );
      } on BusinessRuleFailure catch (failure) {
        if (failure.code != 'ACCOUNT_ALREADY_LINKED' &&
            failure.code != 'INVITE_CLAIMED') {
          rethrow;
        }
      }

      setState(() => _status = 'Signing you in…');
      await ref.read(authApiProvider).connectServer(
            email: preview.email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );

      setState(() => _status = 'Joining ' + preview.businessName + '…');
      final claim = await ref.read(fulusStaffAccessApiProvider).claimInvite(
            token,
            fullName: preview.fullName.isEmpty ? null : preview.fullName,
          );

      ref.read(fulusConnectionStateProvider).markSessionAuthenticated();

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
          _error = _joinErrorMessage(failure);
          _status = '';
        });
      }
    } catch (error) {
      await _clearFailedCloudSession();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'We couldn’t finish joining your business. Please try again.';
          _status = '';
        });
      }
    }
  }

  Future<void> _clearFailedCloudSession() async {
    try {
      await ref.read(apiClientProvider).clearActiveCloudSession();
      ref.read(fulusConnectionStateProvider).disconnect();
      await ref.read(syncServiceProvider).disable();
      await ref.read(authRepositoryProvider).logout();
      ref.read(sessionProvider.notifier).state = null;
    } catch (_) {}
  }

  String _joinErrorMessage(Failure failure) {
    if (failure is NetworkFailure) {
      return 'We couldn’t connect right now. Please try again.';
    }
    if (failure is BusinessRuleFailure &&
        (failure.code?.startsWith('SYNC_') ?? false)) {
      return 'We couldn’t finish joining your business. Please try again.';
    }
    return failure.message;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return FulusScreen(
      title: 'Join your business',
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
                    Icons.badge_rounded,
                    size: 64,
                    color: AppColors.primaryOf(context),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    preview == null ? 'Join your business' : 'You’re invited',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    preview == null
                        ? 'Paste the invitation code your business owner sent you.'
                        : 'Everything is already set up. Choose a password and join.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (preview == null) ...[
                    FulusTextField(
                      label: 'Invitation code',
                      controller: _tokenController,
                      enabled: !_busy,
                      helperText: 'You only need this code once.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FulusButton(
                      label: _busy ? 'Checking invitation…' : 'Continue',
                      loading: _busy,
                      onPressed: _busy ? null : _continueFromInvite,
                    ),
                  ] else ...[
                    FulusCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preview.fullName.isEmpty
                                ? 'Team member'
                                : preview.fullName,
                            style: AppTypography.heading.copyWith(
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            preview.roleName[0].toUpperCase() +
                                preview.roleName.substring(1) +
                                ' · ' +
                                preview.businessName,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            preview.email,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FulusTextField(
                      label: 'Create your Fulus password',
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      helperText:
                          'You will use this password to sign in after logging out.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FulusButton(
                      label: _busy ? 'Setting up Fulus…' : 'Join Fulus',
                      loading: _busy,
                      onPressed: _busy ? null : _join,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FulusButton(
                      label: 'Use a different invitation',
                      variant: FulusButtonVariant.secondary,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _preview = null;
                                _passwordController.clear();
                                _error = null;
                              }),
                    ),
                  ],
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
