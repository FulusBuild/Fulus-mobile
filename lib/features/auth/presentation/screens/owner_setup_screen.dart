import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';

/// The Owner Journey's first step — Volume 3: "create business →
/// (optional setup) → first sale → celebration," now genuinely one
/// combined form rather than a two-step wizard. Onboarding-
/// simplification pass: a real, portable credential (username, email,
/// password) only earns its cost for a future cross-device sync
/// feature that doesn't exist yet — see AuthRepository's own doc
/// comment. Locally, this screen only ever needs to ask for a name.
/// Everything after — printer setup, first product, first sale, the
/// success celebration — stays explicitly optional/deferred, reachable
/// later, never blocking this screen, same as before this pass.
///
/// Two real local calls when both are needed —
/// [AuthRepository.createFirstOwner] then
/// [BusinessSettingsRepository.createBusiness] — but now behind a
/// single submit, not two separate ones: there's no partial identity
/// worth showing a "Next" button for anymore once the credential fields
/// are gone. Still sequential, not simultaneous: the owner identity
/// commits before the business call even starts, so a business-name
/// validation issue never risks re-creating an account that already
/// exists (createFirstOwner is one-shot — see its own doc comment).
///
/// DEAD-END FIX: the pre-simplification version of this screen would
/// let someone fill in the whole business form and only discover, on
/// "Finish," that a business already existed on this device — a banner
/// next to a Finish button that would fail exactly the same way again.
/// This version checks upfront (`_checkIfAlreadyConfigured`, run in
/// initState before any form renders) and, on the same failure surfacing
/// mid-submit anyway (a genuine race, not the common case), routes to
/// the same "you're already set up, tap Continue" recovery state
/// instead of re-showing a doomed form — see [_isFullyConfiguredAlready].
///
/// Volume 3 also specifies business type "pre-configures sensible
/// tax/VAT defaults" and currency "defaulted from the phone's SIM/
/// locale, changeable with one tap." The tax-default mechanism
/// ([BusinessCategoryDefaults]) carries real, sourced per-category
/// numbers; this screen surfaces its `guidance` string under the
/// category list so the default doesn't look arbitrary. SIM/locale
/// currency detection needs a package this project doesn't have (`intl`
/// isn't a dependency) — this defaults to ₦ instead, the currency every
/// persona and example in the Bible itself uses, and stays changeable
/// with one tap via [FulusDropdownField].
///
/// [startAtBusinessStep] / [resumingOwner]: the interrupted-setup
/// recovery path — router.dart's `_ShellGate` resumes here directly
/// (business fields only, owner's name already known) for a signed-in
/// owner whose business was never configured (app killed between the
/// two calls in an earlier session). [resumingOwner] must be supplied
/// whenever [startAtBusinessStep] is true, since there's no name field
/// in this run to have produced it. The name "startAtBusinessStep" is
/// carried over unchanged from before this pass even though "step"
/// undersells it now — it was never worth the churn of renaming across
/// every call site for a purely cosmetic reason.
///
/// [linkToExistingBusiness]: the other interrupted-setup recovery path
/// — [RestoreProgressScreen]'s "Continue Setup" choice, for the mirror
/// case [resolveAuthGateStage] (core/onboarding/onboarding_routing.dart)
/// exists to catch: local business data survives with no matching
/// owner account. Here it's the owner identity that still needs
/// creating and the business call that must NOT run — see
/// [BusinessSettingsRepository.createBusiness]'s own doc comment: it
/// "rejects a second business unconditionally." No business form, no
/// [OnboardingState.armFirstRun] (this isn't a new business, so the
/// onboarding flags are left exactly as they already stand), straight
/// to a signed-in session. Mutually exclusive with [startAtBusinessStep]
/// — one recovers a business missing its owner, the other an owner
/// missing its business.
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
          'exclusive recovery paths — see this class\'s own doc comment.',
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

  // See this class's DEAD-END FIX doc comment above.
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

  /// True if this device already has everything this screen was about
  /// to create — the check the DEAD-END FIX doc comment above describes,
  /// run both proactively (initState, before any form renders) and
  /// reactively (a BusinessRuleFailure caught mid-submit).
  Future<bool> _isFullyConfiguredAlready() async {
    final hasOwner = await ref.read(authRepositoryProvider).hasAnyOwnerAccount();
    if (!hasOwner) return false;
    if (!_needsBusiness) return true; // linkToExistingBusiness: business already existed by definition
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
        // Signs them in immediately — needed even when _needsBusiness is
        // false (linkToExistingBusiness), since nothing else on that
        // path sets the session.
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
        // Silently seeds this business's one default location (Decision
        // 21: "created silently at onboarding, no location UI ever
        // surfacing") — best-effort: ResolveActiveLocation is idempotent
        // and safe to re-run, so a failure here just means the same
        // resolution happens lazily on first use instead.
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {
          // Deliberately swallowed — see comment above.
        }
        if (!mounted) return;
        // Nice-to-have gap closure, Volume 3's onboarding polish — the
        // one moment the app can say "this business is new" with
        // certainty (business creation happens exactly once, right
        // above). Best-effort for the same reason as the location seed.
        try {
          await ref.read(onboardingStateProvider).armFirstRun();
        } catch (_) {
          // Deliberately swallowed — see comment above.
        }
        if (!mounted) return;
        // Only relevant when the guided walkthrough is actually running
        // (this screen reached via GetStartedScreen); a pre-existing
        // install resuming the business call here never armed it in the
        // first place, so walkthroughStep is null and this is a no-op.
        try {
          final onboardingState = ref.read(onboardingStateProvider);
          final step = onboardingState.walkthroughStep;
          if (step == OnboardingStep.businessSetup || step == OnboardingStep.welcome) {
            await onboardingState.advanceWalkthroughTo(OnboardingStep.essentialSettings);
            ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.essentialSettings;
          }
        } catch (_) {
          // Deliberately swallowed — see comment above.
        }
      } else {
        // linkToExistingBusiness — best-effort location seed only, same
        // reasoning as above; a business restored this way already has
        // its own location(s) from before, so this is just the same
        // safety net, not expected to actually do anything here.
        try {
          await ref.read(resolveActiveLocationProvider).call();
        } catch (_) {
          // Deliberately swallowed — see comment above.
        }
      }

      if (!mounted) return;
      // Explicit re-navigation rather than relying on sessionProvider
      // alone having triggered it — the startAtBusinessStep case never
      // touches sessionProvider in this method at all (owner was
      // already signed in before this screen ever showed), so nothing
      // here is guaranteed to make the router re-check on its own.
      context.go('/');
    } on BusinessRuleFailure catch (f) {
      if (!mounted) return;
      if (await _isFullyConfiguredAlready()) {
        // See this class's DEAD-END FIX doc comment — a genuine race
        // rather than the common case, but handled the same way as the
        // proactive initState check: a real way forward, not a banner
        // next to a button that will fail the same way again.
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
                FulusButton(label: 'Continue', onPressed: () => context.go('/')),
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

/// Volume 3's "short tappable list" for business type — a vertical list
/// of five named options rather than [FulusChip]s: chips (5.2) suit
/// compact filters, but these labels ("Restaurant/Food," "Salon/
/// Services") and the fact that exactly one is always selected read
/// more naturally as a list the way [FulusDropdownField]'s own
/// bottom-sheet variant renders options — this reuses that same
/// selected-row visual language directly.
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
