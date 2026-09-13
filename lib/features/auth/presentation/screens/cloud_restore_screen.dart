import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ulid/ulid.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../shared/widgets/widgets.dart';

/// Restores a Fulus installation from an existing Fulus Cloud account.
///
/// A fresh install has no local owner/business rows, so the normal local
/// onboarding gate cannot identify a returning customer. This screen makes
/// the cloud account the recovery identity: authenticate, resolve the user's
/// active business membership, recreate the local business profile, create a
/// local owner identity, and register this installation for future sync.
///
/// The restore intentionally does not require the general sync toggle to be
/// enabled. Reinstall recovery is an explicit user action, so the minimum
/// cloud bootstrap is performed immediately; catalog/location pulls are best
/// effort and can be completed later by the normal sync layer.
class CloudRestoreScreen extends ConsumerStatefulWidget {
  const CloudRestoreScreen({super.key});

  @override
  ConsumerState<CloudRestoreScreen> createState() => _CloudRestoreScreenState();
}

class _CloudRestoreScreenState extends ConsumerState<CloudRestoreScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  String _status = 'Sign in to restore your business.';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your Fulus Cloud email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Signing in…';
    });

    try {
      await ref.read(authApiProvider).connectServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );

      final connection = ref.read(fulusConnectionStateProvider);
      setState(() => _status = 'Finding your business…');
      await connection.refresh();

      final active = connection.membershipContext?.memberships
              .where((membership) => membership.status == 'active')
              .toList(growable: false) ??
          const [];

      if (active.isEmpty) {
        throw StateError(
          'This cloud account has no active Fulus business membership.',
        );
      }
      if (active.length > 1) {
        throw StateError(
          'This account has more than one business. Sign in from Fulus Cloud to choose which business to restore.',
        );
      }

      final businessId = active.single.businessId;
      connection.selectBusiness(businessId);

      setState(() => _status = 'Restoring your business…');
      await ref.read(businessSettingsRepositoryProvider).syncFromServer();

      // The local owner is the device's authentication identity. The cloud
      // account remains the server identity. We deliberately create this
      // only after the business profile exists, so an interrupted restore
      // never leaves a signed-in local owner with no business.
      final owner = await ref.read(authRepositoryProvider).createFirstOwner(
            fullName: _displayNameFromEmail(email),
          );
      ref.read(sessionProvider.notifier).state = owner;

      setState(() => _status = 'Registering this device…');
      await _registerDevice(connection);

      // These are the currently available pull paths that can populate a
      // fresh local database. Failure here must not erase the successfully
      // restored business identity; the normal sync layer can retry them.
      setState(() => _status = 'Restoring products and locations…');
      try {
        await ref.read(locationRepositoryProvider).syncFromServer();
      } catch (_) {
        // Business identity is already restored; location sync can retry.
      }
      try {
        await ref.read(productRepositoryProvider).syncFromServer();
      } catch (_) {
        // Business identity is already restored; product sync can retry.
      }

      if (!mounted) return;
      showFulusSnackbar(context, message: 'Your Fulus business has been restored.');
      context.closeScreenOr('/');
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
          _status = 'Sign in to restore your business.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('Bad state: ', '');
          _status = 'Sign in to restore your business.';
        });
      }
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

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) return 'Owner';
    final words = localPart
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .toList(growable: false);
    return words.isEmpty ? 'Owner' : words.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Restore Fulus',
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in to Fulus Cloud and restore your business to this device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FulusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FulusTextField(
                          label: 'Cloud account email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FulusTextField(
                          label: 'Cloud account password',
                          controller: _passwordController,
                          obscureText: true,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FulusButton(
                          label: 'Restore my business',
                          loading: _busy,
                          onPressed: _busy ? null : _restore,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Your local data stays on this device. Cloud restore recreates the business profile here and brings down the cloud data currently supported by sync.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
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
