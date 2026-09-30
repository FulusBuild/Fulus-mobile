import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../data/remote/endpoints/cloud_restore_api.dart';
import '../../../../data/remote/cross_device_employee_restore.dart';
import '../../../../data/remote/fulus_staff_access_api.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../sync/sync_execution_lease.dart';
import '../../../../sync/sync_user_message.dart';

/// First-device employee onboarding.
///
/// The invitation is the source of truth for the employee's name, email,
/// business, role and access. The employee only enters the invitation code
/// once and then chooses their password. There is deliberately no
/// create-account/sign-in toggle and no second email/name field.
class EmployeeJoinBusinessScreen extends ConsumerStatefulWidget {
  const EmployeeJoinBusinessScreen({super.key});

  @override
  ConsumerState<EmployeeJoinBusinessScreen> createState() => _EmployeeJoinBusinessScreenState();
}

class _EmployeeJoinBusinessScreenState extends ConsumerState<EmployeeJoinBusinessScreen> {
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
      final preview = await ref.read(fulusStaffAccessApiProvider).inspectInvite(token);
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
          _error = syncUserMessage(failure);
          _status = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncUserMessage(error);
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
      _status = 'Signing you in…';
    });

    try {
      var authenticated = false;
      try {
        await ref.read(authApiProvider).connectServer(
              email: preview.email,
              password: password,
              supabaseUrl: SupabaseConfig.url,
              publishableKey: SupabaseConfig.publishableKey,
            );
        authenticated = true;
      } on Failure catch (failure) {
        // Only a definitive user-not-found response permits the signup
        // fallback. Invalid credentials (including a wrong password) must
        // stay on the sign-in path; otherwise a typo in an existing
        // employee's password could trigger an unnecessary account-creation
        // attempt.
        if (failure is! BusinessRuleFailure ||
            failure.code != 'user_not_found') {
          rethrow;
        }
      }

      if (!authenticated) {
        setState(() => _status = 'Creating your Fulus login…');
        final result = await ref.read(authApiProvider).signUpServer(
              email: preview.email,
              password: password,
              supabaseUrl: SupabaseConfig.url,
              publishableKey: SupabaseConfig.publishableKey,
            );

        if (result.session == null) {
          throw StateError(
            'Your Fulus login needs email verification before this phone can join the business.',
          );
        }
      }

      setState(() => _status = 'Joining ${preview.businessName}…');
      final claim = await ref.read(fulusStaffAccessApiProvider).claimInvite(
            token,
            fullName: preview.fullName.isEmpty ? null : preview.fullName,
          );

      final connection = ref.read(fulusConnectionStateProvider);
      connection.markSessionAuthenticated();
      await connection.refresh();
      await connection.selectBusiness(claim.businessId);
      connection.clearSyncReady();

      final snapshot = await CloudRestoreApi(ref.read(apiClientProvider))
          .fetchSnapshot(businessId: claim.businessId);
      final boundary = snapshot['sync_boundary'];
      if (boundary is! num || boundary.toInt() < 0) {
        throw const FormatException('Business restore did not contain a valid sync boundary.');
      }

      setState(() => _status = 'Registering this phone…');
      final storage = ref.read(secureStorageProvider);
      final deviceId = await storage.ensureDeviceClientId(Ulid().toString());
      final package = await PackageInfo.fromPlatform();
      await connection.registerDevice(
        deviceClientId: deviceId,
        deviceName: 'Fulus Mobile',
        platform: Platform.operatingSystem,
        appVersion: package.version,
      );

      setState(() => _status = 'Restoring your business…');
      final localRole = _localRole(claim.roleName);
      final result = await CrossDeviceEmployeeRestore(
        ref.read(databaseProvider),
        executionLease: SyncExecutionLease(ref.read(databaseProvider)),
      ).restore(
        snapshot: snapshot,
        claim: claim,
        settings: CrossDeviceEmployeeRestore.settingsFromSnapshot(snapshot),
        role: localRole,
        onProgress: (status) {
          if (mounted) setState(() => _status = status);
        },
      );

      if (result.totalRows == 0) {
        throw StateError('The cloud business has no restorable business data.');
      }

      setState(() => _status = 'Finishing setup…');
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setInt(
        'fulus_sync_cursor_' + claim.businessId,
        boundary.toInt(),
      );
      if (!saved) {
        throw StateError('Failed to save the cloud restore boundary.');
      }

      await ref.read(syncConfigProvider).setEnabled(true);

      setState(() => _status = 'Checking cloud sync…');
      try {
        await ref.read(syncTriggersProvider).reconcileAfterRestore();
        connection.markSyncReady();
      } catch (error) {
        connection.clearSyncReady();
        connection.markSyncError(error);
        rethrow;
      }

      final employee = await ref.read(authRepositoryProvider).restoreSession();
      if (employee == null || employee.id != claim.userId || !employee.isActive) {
        throw StateError('Employee login was created, but the local session could not be restored.');
      }
      ref.read(sessionProvider.notifier).state = employee;

      if (!mounted) return;
      context.go('/');
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncUserMessage(failure);
          _status = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = syncUserMessage(error);
          _status = '';
        });
      }
    }
  }

  AuthRole _localRole(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'manager':
      case 'admin':
        return AuthRole.manager;
      case 'cashier':
        return AuthRole.cashier;
      default:
        return AuthRole.employee;
    }
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
                            preview.fullName.isEmpty ? 'Team member' : preview.fullName,
                            style: AppTypography.heading.copyWith(
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${preview.roleName[0].toUpperCase()}${preview.roleName.substring(1)} · ${preview.businessName}',
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
                      label: 'Your password',
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      helperText: 'Use your existing Fulus password, or choose a new one.',
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
