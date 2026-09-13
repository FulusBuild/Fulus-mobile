import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ulid/ulid.dart';

import '../../../../../app/providers.dart';
import 'package:fulus_mobile/core/config/supabase_config.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../shared/widgets/widgets.dart';

/// Optional cloud-account linking. Local PIN authentication and local
/// business data remain usable when this connection is absent.
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
  String? _error;

  @override
  void initState() {
    super.initState();
    final name = initialBusinessName?.trim();
    if (name != null && name.isNotEmpty) _businessController.text = name;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _businessController.dispose();
    super.dispose();
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
        showFulusSnackbar(context, message: 'Account created. Check your email to verify it, then return here to finish setup.');
      }
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() { _busy = false; _creatingAccount = false; });
    }
  }

  Future<void> _provisionBusiness() async {
    final name = _businessController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter your business name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authApiProvider).createCloudBusiness(
        name: name,
        functionBaseUrl: SupabaseConfig.functionBaseUrl,
        publishableKey: SupabaseConfig.publishableKey,
      );
      final connection = ref.read(fulusConnectionStateProvider);
      await connection.refresh();
      final active = connection.membershipContext?.memberships
          .where((m) => m.status == 'active').toList(growable: false) ?? const [];
      if (active.length == 1) {
        connection.selectBusiness(active.first.businessId);
        await _registerDevice(connection);
      }
      if (mounted) {
        showFulusSnackbar(context, message: 'You’re ready. Fulus Cloud is connected.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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
      setState(() => _error = 'Enter the cloud account email and password.');
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

      final connection = ref.read(fulusConnectionStateProvider);
      await connection.refresh();

      final active = connection.membershipContext?.memberships
              .where((m) => m.status == 'active')
              .toList(growable: false) ??
          const [];

      if (active.isEmpty) {
        throw StateError(
          'This cloud account has no active Fulus business membership.',
        );
      }

      if (active.length == 1) {
        connection.selectBusiness(active.first.businessId);
        await _registerDevice(connection);
      }

      if (mounted) {
        showFulusSnackbar(
          context,
          message: active.length == 1
              ? 'Fulus Cloud connected.'
              : 'Connected. Select a business below.',
        );
        setState(() => _busy = false);
      }
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

  Future<void> _registerDevice(dynamic connection) async {
    final storage = ref.read(secureStorageProvider);
    final deviceId =
        await storage.ensureDeviceClientId(Ulid().toString());
    final package = await PackageInfo.fromPlatform();

    await connection.registerDevice(
      deviceClientId: deviceId,
      deviceName: 'Fulus Mobile',
      platform: Platform.operatingSystem,
      appVersion: package.version,
    );
  }

  Future<void> _selectBusiness(String businessId) async {
    final connection = ref.read(fulusConnectionStateProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      connection.selectBusiness(businessId);
      await _registerDevice(connection);
      if (mounted) {
        showFulusSnackbar(context, message: 'Business and device connected.');
        setState(() => _busy = false);
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

  Future<void> _disconnect() async {
    ref.read(fulusConnectionStateProvider).disconnect();
    await ref.read(apiClientProvider).clearServerRefreshToken();
    ref.read(apiClientProvider).setAccessToken(null);
    if (mounted) {
      showFulusSnackbar(context, message: 'Fulus Cloud disconnected.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(fulusConnectionStateProvider);
    final memberships = connection.membershipContext?.memberships
            .where((m) => m.status == 'active')
            .toList(growable: false) ??
        const [];
    final connected =
        connection.isConnected && connection.isDeviceAuthorized;

    return FulusScreen(
      title: 'Fulus Cloud',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          FulusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Connected' : 'Optional cloud connection',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  connected
                      ? 'This device is authorized to sync the selected business.'
                      : 'Your local Fulus account and data work without this connection. '
                          'Connect only when you want server-authoritative sync.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (connected)
            FulusButton(
              label: 'Disconnect Cloud',
              variant: FulusButtonVariant.secondary,
              onPressed: _busy ? null : _disconnect,
            )
          else ...[
            FulusCard(
              child: Column(
                children: [
                  FulusTextField(
                    label: 'Cloud account email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  FulusTextField(
                    label: 'Business name (for a new account)',
                    controller: _businessController,
                  ),
                  const SizedBox(height: 12),
                  FulusTextField(
                    label: 'Cloud account password',
                    controller: _passwordController,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(
                      label: 'Connect to Fulus Cloud',
                      loading: _busy && !_creatingAccount,
                      onPressed: _busy ? null : _connect,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FulusButton(
                      label: 'Create account & set up business',
                      variant: FulusButtonVariant.secondary,
                      loading: _busy && _creatingAccount,
                      onPressed: _busy ? null : _createAccount,
                    ),
                  ),
                ],
              ),
            ),
            if (memberships.isNotEmpty) ...[
              const SizedBox(height: 16),
              const FulusSectionHeader(title: 'Businesses'),
              for (final membership in memberships)
                FulusListRow(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(membership.businessId),
                  subtitle: Text(membership.roleId ?? 'Active membership'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy
                      ? null
                      : () => _selectBusiness(membership.businessId),
                ),
            ],
          ],
          if (_error != null && connected) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
