import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import 'cloud_restore_screen.dart';

/// Account-first entry point for a fresh installation.
///
/// The user sees one Fulus account concept rather than having to understand
/// the distinction between a local identity and a cloud account. Existing
/// accounts continue through the canonical restore flow; new accounts create
/// the local business and its cloud membership as one setup journey.
class FulusAccountScreen extends ConsumerStatefulWidget {
  const FulusAccountScreen({super.key});

  @override
  ConsumerState<FulusAccountScreen> createState() => _FulusAccountScreenState();
}

enum _AccountMode { signIn, create }

class _FulusAccountScreenState extends ConsumerState<FulusAccountScreen> {
  final _nameController = TextEditingController();
  final _businessController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _AccountMode _mode = _AccountMode.signIn;
  bool _busy = false;
  bool _awaitingVerification = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _businessController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode(_AccountMode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _error = null;
      _awaitingVerification = false;
    });
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final hasLocalBusiness =
          await ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
      if (hasLocalBusiness) {
        throw StateError(
          'This device already has a business. Sign in from Settings to connect it; '
          'Fulus will not replace or merge your existing local data automatically.',
        );
      }

      await ref.read(authApiProvider).connectServer(
            email: email,
            password: password,
            supabaseUrl: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          );

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const CloudRestoreScreen()),
      );
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    final business = _businessController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || business.isEmpty) {
      setState(() => _error = 'Enter your name and business name.');
      return;
    }
    if (email.isEmpty || password.length < 8) {
      setState(() => _error = 'Enter an email and a password of at least 8 characters.');
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

      if (result.session == null) {
        if (!mounted) return;
        setState(() => _awaitingVerification = true);
        showFulusSnackbar(
          context,
          message: 'Check your email to verify your account, then tap “I’ve verified my email”.',
        );
        return;
      }

      await _finishNewAccount(name: name, businessName: business);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAndFinish() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the same email and password you used to create the account.');
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
      await _finishNewAccount(
        name: _nameController.text.trim(),
        businessName: _businessController.text.trim(),
      );
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishNewAccount({required String name, required String businessName}) async {
    if (name.isEmpty || businessName.isEmpty) {
      throw StateError('Your name and business name are required to finish setup.');
    }

    final authRepository = ref.read(authRepositoryProvider);
    final businessRepository = ref.read(businessSettingsRepositoryProvider);

    // Keep local-first semantics: establish the local owner/business before
    // enabling sync. If cloud provisioning later fails, the business remains
    // usable offline and can be connected again from Settings.
    final owner = await authRepository.createFirstOwner(fullName: name);
    if (!mounted) return;
    ref.read(sessionProvider.notifier).state = owner;

    await businessRepository.createBusiness(
      businessName: businessName,
      category: BusinessCategory.retailShop,
      currencySymbol: '₦',
    );

    await ref.read(authApiProvider).createCloudBusiness(
          name: businessName,
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
      throw StateError('Your account was created, but the business connection is not ready yet.');
    }

    connection.selectBusiness(active.single.businessId);
    await ref.read(syncConfigProvider).setEnabled(true);

    if (!mounted) return;
    showFulusSnackbar(
      context,
      message: 'Your Fulus account is ready. Your business will sync automatically when you’re online.',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final creating = _mode == _AccountMode.create;
    return FulusScreen(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: FulusBrandLogo(size: 72, padding: 10, backgroundColor: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    creating ? 'Create your Fulus account' : 'Welcome to Fulus',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    creating
                        ? 'One account for your business. Your work stays on this device and backs up automatically.'
                        : 'Sign in to your Fulus account to bring your business back to this device.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FulusCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (creating) ...[
                          FulusTextField(label: 'Your name', controller: _nameController, enabled: !_busy),
                          const SizedBox(height: AppSpacing.md),
                          FulusTextField(label: 'Business name', controller: _businessController, enabled: !_busy),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        FulusTextField(
                          label: 'Email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_busy,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FulusTextField(
                          label: 'Password',
                          controller: _passwordController,
                          obscureText: true,
                          enabled: !_busy,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        if (_awaitingVerification) ...[
                          FulusButton(
                            label: 'I’ve verified my email',
                            loading: _busy,
                            onPressed: _busy ? null : _verifyAndFinish,
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        FulusButton(
                          label: creating ? 'Create account' : 'Sign in',
                          loading: _busy,
                          onPressed: _busy ? null : (creating ? _createAccount : _signIn),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _switchMode(creating ? _AccountMode.signIn : _AccountMode.create),
                      child: Text(creating ? 'I already have an account' : 'Create a Fulus account'),
                    ),
                  ),
                  if (!creating)
                    Center(
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push<void>(
                                  MaterialPageRoute(builder: (_) => const CloudRestoreScreen()),
                                ),
                        child: const Text('Restore my business'),
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
