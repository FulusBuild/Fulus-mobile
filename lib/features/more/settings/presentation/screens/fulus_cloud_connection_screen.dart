import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ulid/ulid.dart';

import '../../../../../app/providers.dart';
import '../../../../../core/config/supabase_config.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Connects an already-running local business to a Fulus account.
///
/// This screen never restores a cloud business over local data. A new cloud
/// account can be created for the local business, or an existing account with
/// no business can be connected to it. If an existing account already owns a
/// business, restore belongs to fresh-install setup and this screen refuses
/// to merge the two businesses.
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
  bool _creatingAccount = false;
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
      final settings = await ref.read(businessSettingsRepositoryProvider).watchSettings().first;
      final name = settings?.businessName.trim();
      if (!mounted || name == null || name.isEmpty || _businessController.text.isNotEmpty) return;
      setState(() => _businessController.text = name);
    } catch (_) {
      // The field remains editable; failure to prefill must not block linking.
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
        message: 'A fresh verification email has been sent. Open the newest email and try again.',
      );
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _resendingVerification = false);
    }
  }

  Future<void> _createAccount() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 8) {
      setState(() => _error = 'Enter an email and a password of at least 8 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _creatingAccount = true;
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
          message: 'Check your email to verify your account, then tap “I’ve verified my email”.',
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
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() { _busy = false; _creatingAccount = false; });
    }
  }

  Future<void> _checkVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the same email and password you used to create the account.');
      return;
    }

    setState(() { _busy = true; _error = null; });
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
      if (mounted) setState(() { _busy = false; _error = failure.message; });
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.toString().replaceFirst('Bad state: ', ''); });
    }
  }

  Future<void> _provisionBusiness() async {
    final name = _businessController.text.trim();
    if (name.length < 2) {
      if (mounted) setState(() => _error = 'Enter your business name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authApiProvider).createCloudBusiness(
        name: name,
        functionBaseUrl: SupabaseConfig.functionBaseUrl,
        businessProvisionFunctionUrl: SupabaseConfig.businessProvisionFunctionUrl,
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
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the account email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _creatingAccount = false;
      _error = null;
    });

    try {
      await ref.read(authApiProvider).connectServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );

      final connection = ref.read(fulusConnectionStateProvider);
      await connection.refresh();
      final active = connection.membershipContext?.memberships
              .where((membership) => membership.status == 'active')
              .toList(growable: false) ??
          const [];

      // An account that already owns a business belongs to the fresh-install
      // restore path. Never point this local business at it and never merge
      // two businesses implicitly.
      if (active.isNotEmpty) {
        throw StateError(
          'This account already has a Fulus business. To use that business on this device, restore it during fresh setup. Fulus will not merge it with this local business.',
        );
      }

      await _provisionBusiness();
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure.message;
          if (failure.message.toLowerCase().contains('verify your email')) {
            _awaitingVerification = true;
          }
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
        message: 'Your business is connected. Fulus will back it up automatically when you’re online.',
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
      showFulusSnackbar(context, message: 'Cloud backup disconnected. Your local data is still safe.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(fulusConnectionStateProvider);
    final connected = connection.isConnected && connection.isDeviceAuthorized;

    return FulusScreen(
      title: 'Account & Backup',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FulusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connected ? 'Backup is on' : 'Connect your Fulus account', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(connected
                    ? 'Your business stays on this device and is backed up automatically when you’re online.'
                    : 'Fulus works without internet. Connect an account to back up this local business and use it on other devices.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (connected)
            FulusButton(
              label: 'Disconnect account',
              variant: FulusButtonVariant.secondary,
              onPressed: _busy ? null : _disconnect,
            )
          else
            FulusCard(
              child: Column(
                children: [
                  FulusTextField(label: 'Email', controller: _emailController, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  FulusTextField(label: 'Business name', controller: _businessController),
                  const SizedBox(height: 12),
                  FulusTextField(label: 'Password', controller: _passwordController, obscureText: true),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                  ],
                  if (_awaitingVerification) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FulusButton(label: 'I’ve verified my email', loading: _busy, onPressed: _busy ? null : _checkVerification),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FulusButton(label: 'Resend verification email', variant: FulusButtonVariant.secondary, loading: _resendingVerification, onPressed: _busy || _resendingVerification ? null : _resendVerification),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(label: 'Connect account', loading: _busy && !_creatingAccount, onPressed: _busy ? null : _connect),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(label: 'Create account & back up this business', variant: FulusButtonVariant.secondary, loading: _busy && _creatingAccount, onPressed: _busy ? null : _createAccount),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
