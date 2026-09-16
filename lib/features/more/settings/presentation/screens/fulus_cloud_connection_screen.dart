import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ulid/ulid.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/config/supabase_config.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/theme/design_tokens.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Creates a new Fulus account for an already-running local business.
///
/// This screen is intentionally creation-only. An existing cloud account or
/// cloud business belongs to the account/restore flow during fresh setup and
/// must never be merged implicitly with this local business.
class FulusCloudConnectionScreen extends ConsumerStatefulWidget {
  const FulusCloudConnectionScreen({super.key, this.initialBusinessName});

  final String? initialBusinessName;

  @override
  ConsumerState<FulusCloudConnectionScreen> createState() =>
      _FulusCloudConnectionScreenState();
}

class _FulusCloudConnectionScreenState
    extends ConsumerState<FulusCloudConnectionScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _businessController = TextEditingController();
  bool _busy = false;
  bool _resendingVerification = false;
  bool _awaitingVerification = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = widget.initialBusinessName?.trim();
    if (name != null && name.isNotEmpty) {
      _businessController.text = name;
    } else {
      unawaited(_loadLocalBusinessName());
    }
  }

  Future<void> _loadLocalBusinessName() async {
    try {
      final settings = await ref
          .read(businessSettingsRepositoryProvider)
          .watchSettings()
          .first;
      final name = settings?.businessName.trim();
      if (!mounted ||
          name == null ||
          name.isEmpty ||
          _businessController.text.isNotEmpty) {
        return;
      }
      setState(() => _businessController.text = name);
    } catch (_) {
      // The field remains editable; failure to prefill must not block setup.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _businessController.dispose();
    super.dispose();
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    setState(() {
      _resendingVerification = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).resendSignupVerification(
            email: email,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );
      if (!mounted) return;
      showFulusSnackbar(
        context,
        message:
            'A fresh verification email has been sent. Open the newest email and try again.',
      );
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _resendingVerification = false);
    }
  }

  Future<void> _createAccount() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 8) {
      setState(
        () => _error =
            'Enter an email and a password of at least 8 characters.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref.read(authApiProvider).signUpServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );
      if (!mounted) return;
      if (result.session != null) {
        await _provisionBusiness();
      } else {
        setState(() => _awaitingVerification = true);
        showFulusSnackbar(
          context,
          message:
              'Check your email to verify your account, then tap “I’ve verified my email”.',
        );
      }
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          if (failure.message.toLowerCase().contains('verify your email')) {
            _awaitingVerification = true;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _checkVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(
        () => _error =
            'Enter the same email and password you used to create the account.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).connectServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );
      if (!mounted) return;
      setState(() => _awaitingVerification = false);
      await _provisionBusiness();
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  Future<void> _provisionBusiness() async {
    final name = _businessController.text.trim();
    if (name.length < 2) {
      if (mounted) setState(() => _error = 'Enter your business name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).createCloudBusiness(
            name: name,
            functionBaseUrl: SupabaseConfig.functionBaseUrl,
            businessProvisionFunctionUrl:
                SupabaseConfig.businessProvisionFunctionUrl,
            publishableKey: SupabaseConfig.publishableKey,
          );
      final connection = ref.read(fulusConnectionStateProvider);
      await connection.refresh();
      final active = connection.membershipContext?.memberships
              .where((membership) => membership.status == 'active')
              .toList(growable: false) ??
          const [];
      if (active.length != 1) {
        throw StateError(
          'Business setup completed, but the new business connection is not ready yet. Please try again in a moment.',
        );
      }
      connection.selectBusiness(active.single.businessId);
      await _finishCloudConnection(connection);
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishCloudConnection(dynamic connection) async {
    await _registerDevice(connection);

    // A local business may contain historical rows created before cloud
    // backup existed. Seed those rows into the same durable, dependency-
    // ordered queue used by normal writes before the first reconciliation.
    await ref.read(syncQueueProvider).seedExistingBusinessData();

    final syncConfig = ref.read(syncConfigProvider);
    final syncTriggers = ref.read(syncTriggersProvider);
    await syncConfig.setEnabled(true);
    try {
      await syncTriggers.reconcileAfterRestore();
      connection.markSyncReady();
    } catch (_) {
      connection.clearSyncReady();
      rethrow;
    }

    if (mounted) {
      showFulusSnackbar(
        context,
        message:
            'Your business is connected. Fulus will back it up automatically when you’re online.',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _registerDevice(dynamic connection) async {
    final storage = ref.read(secureStorageProvider);
    final deviceId = await storage.ensureDeviceClientId(Ulid().toString());
    final package = await PackageInfo.fromPlatform();

    await connection.registerDevice(
      deviceClientId: deviceId,
      deviceName: 'Fulus Mobile',
      platform: Platform.operatingSystem,
      appVersion: package.version,
    );
  }

  Future<void> _disconnect() async {
    ref.read(fulusConnectionStateProvider).disconnect();
    await ref.read(apiClientProvider).clearServerRefreshToken();
    ref.read(apiClientProvider).setAccessToken(null);
    await ref.read(syncConfigProvider).setEnabled(false);
    if (mounted) {
      showFulusSnackbar(
        context,
        message: 'Cloud backup disconnected. Your local data is still safe.',
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(fulusConnectionStateProvider);
    final connected = connection.isConnected && connection.isDeviceAuthorized;
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return FulusScreen(
      title: 'Account & Backup',
      subtitle: connected
          ? 'Your business backup and cloud connection'
          : 'Protect this business without changing your local data',
      body: ListView(
        padding: EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FulusCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primaryOf(context)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            connected
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_outlined,
                            color: AppColors.primaryOf(context),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connected ? 'Fulus Cloud' : 'Back up your business',
                                style: AppTypography.heading.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                connected
                                    ? 'Connected and ready to keep your business data backed up when you’re online.'
                                    : 'Create a Fulus account to protect this local business and use it on other devices.',
                                style: AppTypography.body.copyWith(
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: connected
                                          ? AppColors.successOf(context)
                                          : AppColors.textSecondaryOf(context),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    connected ? 'Backup is on' : 'Not connected',
                                    style: AppTypography.caption.copyWith(
                                      color: connected
                                          ? AppColors.successOf(context)
                                          : AppColors.textSecondaryOf(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (connected) ...[
                    FulusSectionHeader(
                      title: 'Account & Backup',
                      subtitle: 'Cloud backup for this business',
                    ),
                    FulusCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FulusListRow(
                            leading: const Icon(Icons.cloud_done_outlined),
                            title: const Text('Fulus Cloud'),
                            subtitle: const Text('Connected and syncing when online'),
                            trailing: const Icon(Icons.check_circle_outline),
                          ),
                          const FulusListDivider(),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: SizedBox(
                              width: isWide ? 240 : double.infinity,
                              child: FulusButton(
                                label: 'Disconnect account',
                                variant: FulusButtonVariant.secondary,
                                onPressed: _busy ? null : _disconnect,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    FulusSectionHeader(
                      title: 'Fulus Cloud',
                      subtitle: 'Create your account and connect this business',
                    ),
                    FulusCard(
                      child: Column(
                        children: [
                          FulusTextField(
                            label: 'Email',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FulusTextField(
                            label: 'Business name',
                            controller: _businessController,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FulusTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (_error != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.errorOf(context)
                                    .withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(
                                  color: AppColors.errorOf(context)
                                      .withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: AppTypography.body.copyWith(
                                  color: AppColors.errorOf(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          if (_awaitingVerification) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FulusButton(
                                label: 'I’ve verified my email',
                                loading: _busy,
                                onPressed: _busy ? null : _checkVerification,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: FulusButton(
                                label: 'Resend verification email',
                                variant: FulusButtonVariant.secondary,
                                loading: _resendingVerification,
                                onPressed: _busy || _resendingVerification
                                    ? null
                                    : _resendVerification,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FulusButton(
                              label: 'Create account & back up this business',
                              loading: _busy,
                              onPressed: _busy ? null : _createAccount,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: Text(
                        'Your business remains local-first. Connecting Cloud adds backup and sync; it does not replace the data already on this device.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
