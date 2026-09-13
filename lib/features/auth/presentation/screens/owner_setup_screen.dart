import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';

/// The first-run setup is intentionally local-first and minimal.
///
/// A new owner only needs to provide their name and business name. Fulus
/// supplies sensible defaults for the other configuration values so a
/// non-technical shop owner can start selling immediately. Cloud, printers,
/// locations and advanced configuration remain available later.
class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({
    super.key,
    this.startAtBusinessStep = false,
    this.resumingOwner,
    this.linkToExistingBusiness = false,
  })  : assert(
          !startAtBusinessStep || resumingOwner != null,
          'resumingOwner is required when starting at the business step.',
        ),
        assert(
          !(startAtBusinessStep && linkToExistingBusiness),
          'startAtBusinessStep and linkToExistingBusiness are mutually '
          'exclusive recovery paths.',
        );

  final bool startAtBusinessStep;
  final AuthUser? resumingOwner;
  final bool linkToExistingBusiness;

  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  final _fullNameController = TextEditingController();
  final _businessNameController = TextEditingController();

  bool _submitting = false;
  String? _bannerMessage;
  Map<String, String> _fieldErrors = {};
  bool _checkingExisting = true;
  bool _alreadyConfigured = false;

  bool get _needsOwnerName => !widget.startAtBusinessStep;
  bool get _needsBusiness => !widget.linkToExistingBusiness;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyConfigured();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  Future<bool> _isFullyConfiguredAlready() async {
    final hasOwner = await ref.read(authRepositoryProvider).hasAnyOwnerAccount();
    if (!hasOwner) return false;
    if (!_needsBusiness) return true;
    return ref.read(businessSettingsRepositoryProvider).hasBeenConfigured();
  }

  Future<void> _checkIfAlreadyConfigured() async {
    final already = await _isFullyConfiguredAlready();
    if (!mounted) return;
    setState(() {
      _alreadyConfigured = already;
      _checkingExisting = false;
    });
  }

  void _clearErrors() {
    if (_bannerMessage != null || _fieldErrors.isNotEmpty) {
      setState(() {
        _bannerMessage = null;
        _fieldErrors = {};
      });
    }
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final businessName = _businessNameController.text.trim();
    final errors = <String, String>{};

    if (_needsOwnerName && fullName.isEmpty) {
      errors['fullName'] = 'Enter your name.';
    }
    if (_needsBusiness) {
      if (businessName.isEmpty) {
        errors['businessName'] = "What's your business called?";
      } else if (businessName.length > 150) {
        errors['businessName'] = 'Keep this under 150 characters.';
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
      _fieldErrors = {};
    });

    try {
      AuthUser owner;
      if (_needsOwnerName) {
        owner = await ref.read(authRepositoryProvider).createFirstOwner(fullName: fullName);
        if (!mounted) return;
        ref.read(sessionProvider.notifier).state = owner;
      } else {
        owner = widget.resumingOwner!;
      }

      if (_needsBusiness) {
        await ref.read(businessSettingsRepositoryProvider).createBusiness(
              businessName: businessName,
              category: BusinessCategory.retailShop,
              currencySymbol: '₦',
            );
        if (!mounted) return;
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {}
        if (!mounted) return;
        try {
          await ref.read(onboardingStateProvider).armFirstRun();
        } catch (_) {}
      } else {
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {}
      }

      if (!mounted) return;
      // A new business goes straight to the lightweight first-run handoff.
      // Optional walkthrough steps are never allowed to block the first sale.
      if (widget.startAtBusinessStep || widget.linkToExistingBusiness) {
        context.closeScreenOr('/');
      } else {
        context.go('/');
      }
    } on BusinessRuleFailure catch (f) {
      if (!mounted) return;
      if (await _isFullyConfiguredAlready()) {
        setState(() => _alreadyConfigured = true);
      } else {
        setState(() => _bannerMessage = f.message);
      }
    } on ValidationFailure catch (v) {
      if (!mounted) return;
      setState(() => _fieldErrors = v.fieldErrors);
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _bannerMessage = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingExisting) {
      return const FulusScreen(body: FulusLoadingIndicator());
    }
    if (_alreadyConfigured) return _buildAlreadySetUp(context);

    final title = !_needsBusiness
        ? 'Finish setting up'
        : !_needsOwnerName
            ? 'Tell us about your business'
            : "Let's get started";

    return FulusScreen(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _needsOwnerName
                        ? 'Your name and your business. Nothing else is required.'
                        : 'Just your business name. You can configure the rest later.',
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (_bannerMessage != null) ...[
                    AuthErrorBanner(message: _bannerMessage!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (_needsOwnerName) ...[
                    FulusTextField(
                      label: 'Your name',
                      controller: _fullNameController,
                      errorText: _fieldErrors['fullName'],
                      onChanged: (_) => _clearErrors(),
                    ),
                    if (_needsBusiness) const SizedBox(height: AppSpacing.lg),
                  ],
                  if (_needsBusiness)
                    FulusTextField(
                      label: 'Business name',
                      controller: _businessNameController,
                      errorText: _fieldErrors['businessName'],
                      onChanged: (_) => _clearErrors(),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  FulusButton(
                    label: !_needsBusiness ? 'Finish' : 'Create my business',
                    icon: Icons.arrow_forward_rounded,
                    loading: _submitting,
                    onPressed: _submitting ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlreadySetUp(BuildContext context) {
    return FulusScreen(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.check_circle_outline, color: AppColors.primaryOf(context), size: AppIconSize.hero),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  "You're all set",
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This business is already set up on this device.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(label: 'Continue', onPressed: () => context.closeScreenOr('/')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
