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
import '../../../../data/remote/cloud_restore_api.dart';
import '../../../../data/remote/cross_device_employee_restore.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../sync/sync_execution_lease.dart';
import '../../../../sync/sync_user_message.dart';

/// First-device entry point for an employee who was invited by a Fulus
/// business. This is separate from the local "Who's this?" picker: the
/// latter only switches identities already materialized on this phone.
class EmployeeJoinBusinessScreen extends ConsumerStatefulWidget {
  const EmployeeJoinBusinessScreen({super.key});

  @override
  ConsumerState<EmployeeJoinBusinessScreen> createState() => _EmployeeJoinBusinessScreenState();
}

class _EmployeeJoinBusinessScreenState extends ConsumerState<EmployeeJoinBusinessScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _createAccount = true;
  bool _busy = false;
  String? _error;
  String _status = '';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final token = _tokenController.text.trim();

    if (token.isEmpty) {
      setState(() => _error = 'Enter the invitation code from your business owner.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the email address the invitation was sent to.');
      return;
    }
    if (_createAccount && name.length < 2) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Use a password of at least 8 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = _createAccount ? 'Creating your Fulus account…' : 'Signing you in…';
    });

    try {
      if (_createAccount) {
        final result = await ref.read(authApiProvider).signUpServer(
              email: email,
              password: password,
              supabaseUrl: SupabaseConfig.url,
              publishableKey: SupabaseConfig.publishableKey,
            );
        if (result.session == null) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _createAccount = false;
            _status = '';
            _error = result.emailConfirmed
                ? 'Your account was created. Sign in below to continue.'
                : 'Check your email to verify your account, then sign in below.';
          });
          return;
        }
      } else {
        await ref.read(authApiProvider).connectServer(
              email: email,
              password: password,
              supabaseUrl: SupabaseConfig.url,
              publishableKey: SupabaseConfig.publishableKey,
            );
      }

      setState(() => _status = 'Joining your business…');
      final claim = await ref.read(fulusStaffAccessApiProvider).claimInvite(
            token,
            fullName: name.isEmpty ? null : name,
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

      setState(() => _status = 'Preparing cloud sync…');
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
                    'Use Fulus on your phone',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter the invitation code from your business owner. Your account, role and access will be restored to this phone.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: FulusButton(
                          label: 'Create account',
                          variant: _createAccount
                              ? FulusButtonVariant.primary
                              : FulusButtonVariant.secondary,
                          onPressed: _busy ? null : () => setState(() => _createAccount = true),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FulusButton(
                          label: 'Sign in',
                          variant: !_createAccount
                              ? FulusButtonVariant.primary
                              : FulusButtonVariant.secondary,
                          onPressed: _busy ? null : () => setState(() => _createAccount = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FulusTextField(
                    label: 'Invitation code',
                    controller: _tokenController,
                    enabled: !_busy,
                    helperText: 'Paste the code shared by your business owner.',
                  ),
                  if (_createAccount) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FulusTextField(
                      label: 'Full name',
                      controller: _nameController,
                      enabled: !_busy,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  FulusTextField(
                    label: 'Email',
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusTextField(
                    label: 'Password',
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
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
                  const SizedBox(height: AppSpacing.lg),
                  FulusButton(
                    label: _busy ? 'Setting up Fulus…' : 'Join business',
                    loading: _busy,
                    onPressed: _busy ? null : _submit,
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
