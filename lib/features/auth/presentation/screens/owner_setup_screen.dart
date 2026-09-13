import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/screen_exit.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';
import '../../../more/settings/presentation/screens/fulus_cloud_connection_screen.dart';

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
  BusinessCategory _category = BusinessCategory.retailShop;
  String _currencySymbol = '₦';

  bool _submitting = false;
  String? _bannerMessage;
  Map<String, String> _fieldErrors = {};
  bool _checkingExisting = true;
  bool _alreadyConfigured = false;

  bool get _needsOwnerName => !widget.startAtBusinessStep;
  bool get _needsBusiness => !widget.linkToExistingBusiness;

  static const List<FulusDropdownOption<String>> _currencyOptions = [
    FulusDropdownOption(value: '₦', label: '₦ Naira'),
    FulusDropdownOption(value: r'$', label: r'$ Dollar'),
    FulusDropdownOption(value: '€', label: '€ Euro'),
    FulusDropdownOption(value: '£', label: '£ Pound'),
    FulusDropdownOption(value: 'GH₵', label: 'GH₵ Cedi'),
    FulusDropdownOption(value: 'R', label: 'R Rand'),
  ];

  static const _categoryLabels = {
    BusinessCategory.retailShop: 'Retail Shop',
    BusinessCategory.restaurantOrFood: 'Restaurant/Food',
    BusinessCategory.pharmacy: 'Pharmacy',
    BusinessCategory.salonOrServices: 'Salon/Services',
    BusinessCategory.other: 'Other',
  };

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
      errors['fullName'] = 'Enter your full name.';
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
              category: _category,
              currencySymbol: _currencySymbol,
            );
        if (!mounted) return;
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {}
        if (!mounted) return;
        try {
          await ref.read(onboardingStateProvider).armFirstRun();
        } catch (_) {}
        if (!mounted) return;
        try {
          final onboardingState = ref.read(onboardingStateProvider);
          final step = onboardingState.walkthroughStep;
          if (step == OnboardingStep.businessSetup || step == OnboardingStep.welcome) {
            await onboardingState.advanceWalkthroughTo(OnboardingStep.essentialSettings);
            ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.essentialSettings;
          }
        } catch (_) {}
      } else {
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {}
      }

      if (!mounted) return;
      if (widget.startAtBusinessStep || widget.linkToExistingBusiness) {
        context.closeScreenOr('/');
      } else {
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => FulusCloudConnectionScreen(
              initialBusinessName: businessName,
            ),
          ),
        );
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
      return const FulusScreen(body: Center(child: CircularProgressIndicator()));
    }
    if (_alreadyConfigured) {
      return _buildAlreadySetUp(context);
    }

    final title = !_needsBusiness
        ? 'Finish setting up'
        : !_needsOwnerName
            ? 'Tell us about your business'
            : "Let's get started";
    final subtitle = !_needsBusiness
        ? null
        : !_needsOwnerName
            ? null
            : 'Just your name and your business — that\'s it.';

    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ],
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
                if (_needsBusiness) _buildBusinessFields(context),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: !_needsBusiness ? 'Finish' : 'Get started',
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
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
                Icon(
                  Icons.check_circle_outline,
                  color: AppColors.primaryOf(context),
                  size: AppIconSize.hero,
                ),
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

  Widget _buildBusinessFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FulusTextField(
          label: 'Business name',
          controller: _businessNameController,
          errorText: _fieldErrors['businessName'],
          onChanged: (_) => _clearErrors(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusSectionHeader(title: 'Business type'),
        for (final category in BusinessCategory.values) ...[
          _CategoryOption(
            label: _categoryLabels[category]!,
            selected: _category == category,
            onTap: () => setState(() => _category = category),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            BusinessCategoryDefaults.forCategory(_category).guidance,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FulusDropdownField<String>(
          label: 'Currency',
          options: _currencyOptions,
          value: _currencySymbol,
          onChanged: (value) => setState(() => _currencySymbol = value),
        ),
      ],
    );
  }
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(
                color: selected ? AppColors.primaryOf(context) : AppColors.textPrimaryOf(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_circle, color: AppColors.primaryOf(context), size: AppIconSize.compact),
        ],
      ),
    );
  }
}
