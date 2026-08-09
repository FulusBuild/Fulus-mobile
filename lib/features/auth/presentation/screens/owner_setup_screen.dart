import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/security/password_policy.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/business_category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/auth_error_banner.dart';

/// The Owner Journey's first two steps — Volume 3: "create business →
/// (optional setup) → first sale → celebration." This screen covers
/// exactly the first arrow: account + business creation. Everything
/// after — printer setup, first product, first sale, the success
/// celebration — is explicitly optional/deferred per Volume 3 itself
/// ("Nothing else is asked here... reachable later, never blocking
/// this screen") and belongs to Sell/Stock, not this foundation phase;
/// this screen's only job is to land a real, signed-in owner with a
/// real business profile into the app shell.
///
/// Two real network-free calls, not one — [AuthRepository.
/// createFirstOwner] then [BusinessSettingsRepository.createBusiness],
/// exactly as both interfaces' own doc comments describe: "two steps of
/// the same first-run onboarding flow (separate repositories, no
/// code-level coupling between them) — whichever screen ends up driving
/// onboarding is responsible for calling both." Sequential, not
/// simultaneous: Step 1 commits the account for real before Step 2 even
/// renders, so a Step 2 failure (a business-name validation issue, say)
/// never risks re-asking for account details that already exist.
/// There's deliberately no "back" from Step 2 to Step 1 for the same
/// reason — nothing here can edit or undo an already-created account.
///
/// Volume 3 also specifies business type "pre-configures sensible
/// tax/VAT defaults" and currency "defaulted from the phone's SIM/
/// locale, changeable with one tap." The tax-default mechanism exists
/// ([BusinessCategoryDefaults]) but every category currently resolves
/// to the same placeholder numbers — that's business_category.dart's
/// own honestly-flagged gap, not something this screen re-decides.
/// SIM/locale currency detection needs a package this project doesn't
/// have (`intl` isn't a dependency) — this defaults to ₦ instead, the
/// currency every persona and example in the Bible itself uses, and
/// stays changeable with one tap via [FulusDropdownField], which is at
/// least faithful to the "one tap" part of the spec even though the
/// "defaulted from SIM" part is a reasonable substitute, not the real
/// mechanism.
///
/// [startAtBusinessStep] / [resumingOwner]: the interrupted-setup
/// recovery path — router.dart's `_ShellGate` resumes here directly at
/// Step 2 for a signed-in owner whose business was never configured
/// (app killed between the two steps in an earlier session; the
/// account is real and already signed in, only the business step never
/// ran). [resumingOwner] must be supplied whenever [startAtBusinessStep]
/// is true, since there's no Step 1 in this run to have produced it.
class OwnerSetupScreen extends ConsumerStatefulWidget {
  const OwnerSetupScreen({
    super.key,
    this.startAtBusinessStep = false,
    this.resumingOwner,
  }) : assert(
          !startAtBusinessStep || resumingOwner != null,
          'resumingOwner is required when starting at the business step.',
        );

  final bool startAtBusinessStep;
  final AuthUser? resumingOwner;

  @override
  ConsumerState<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends ConsumerState<OwnerSetupScreen> {
  late int _step = widget.startAtBusinessStep ? 1 : 0;
  late AuthUser? _createdOwner = widget.resumingOwner;

  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;

  final _businessNameController = TextEditingController();
  BusinessCategory _category = BusinessCategory.retailShop;
  String _currencySymbol = '₦';

  bool _submitting = false;
  String? _bannerMessage;
  Map<String, String> _fieldErrors = {};

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
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _businessNameController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    if (_bannerMessage != null || _fieldErrors.isNotEmpty) {
      setState(() {
        _bannerMessage = null;
        _fieldErrors = {};
      });
    }
  }

  Future<void> _submitAccount() async {
    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final errors = <String, String>{};
    if (fullName.isEmpty) errors['fullName'] = 'Enter your full name.';
    if (username.isEmpty) errors['username'] = 'Choose a username.';
    if (email.isEmpty || !email.contains('@')) errors['email'] = 'Enter a valid email address.';
    // Client-side, using the exact same policy the repository itself
    // enforces (PasswordPolicy.validate) — not a separate, potentially
    // drifting copy of the rule, just called a step earlier so a weak
    // password never even reaches a repository round trip.
    try {
      if (password.isNotEmpty) PasswordPolicy.validate(password);
      if (password.isEmpty) errors['password'] = 'Choose a password.';
    } on ValidationFailure catch (v) {
      errors.addAll(v.fieldErrors);
    }
    if (confirmPassword != password) {
      errors['confirmPassword'] = "Passwords don't match.";
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
      final owner = await ref.read(authRepositoryProvider).createFirstOwner(
            username: username,
            email: email,
            fullName: fullName,
            password: password,
          );
      if (!mounted) return;
      setState(() {
        _createdOwner = owner;
        _step = 1;
      });
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

  Future<void> _submitBusiness() async {
    final businessName = _businessNameController.text.trim();
    if (businessName.isEmpty) {
      setState(() => _fieldErrors = {'businessName': "What's your business called?"});
      return;
    }
    if (businessName.length > 150) {
      setState(() => _fieldErrors = {'businessName': 'Keep this under 150 characters.'});
      return;
    }

    setState(() {
      _submitting = true;
      _bannerMessage = null;
      _fieldErrors = {};
    });
    try {
      await ref.read(businessSettingsRepositoryProvider).createBusiness(
            businessName: businessName,
            category: _category,
            currencySymbol: _currencySymbol,
          );
      if (!mounted) return;
      // Only now — both steps genuinely complete — does the app
      // actually consider this a signed-in session for navigation
      // purposes. See this file's own header comment and
      // providers.dart's sessionProvider for why this write is what
      // actually moves the router from AuthGateScreen into the shell.
      ref.read(sessionProvider.notifier).state = _createdOwner;
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _bannerMessage = f.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  'Step ${_step + 1} of 2',
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(color: AppColors.primaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _step == 0 ? "Let's set up your account" : 'Tell us about your business',
                  textAlign: TextAlign.center,
                  style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_bannerMessage != null) ...[
                  AuthErrorBanner(message: _bannerMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_step == 0) _buildAccountStep(context) else _buildBusinessStep(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FulusTextField(
          label: 'Full name',
          controller: _fullNameController,
          errorText: _fieldErrors['fullName'],
          onChanged: (_) => _clearErrors(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusTextField(
          label: 'Username',
          controller: _usernameController,
          errorText: _fieldErrors['username'],
          onChanged: (_) => _clearErrors(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusTextField(
          label: 'Email',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          errorText: _fieldErrors['email'],
          onChanged: (_) => _clearErrors(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusTextField(
          label: 'Password',
          controller: _passwordController,
          obscureText: _obscurePassword,
          errorText: _fieldErrors['password'],
          helperText: 'At least 8 characters, with a letter and a number.',
          onChanged: (_) => _clearErrors(),
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FulusTextField(
          label: 'Confirm password',
          controller: _confirmPasswordController,
          obscureText: _obscurePassword,
          errorText: _fieldErrors['confirmPassword'],
          onChanged: (_) => _clearErrors(),
        ),
        const SizedBox(height: AppSpacing.xl),
        FulusButton(
          label: 'Next',
          loading: _submitting,
          onPressed: _submitting ? null : _submitAccount,
        ),
      ],
    );
  }

  Widget _buildBusinessStep(BuildContext context) {
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
        const SizedBox(height: AppSpacing.sm),
        FulusDropdownField<String>(
          label: 'Currency',
          options: _currencyOptions,
          value: _currencySymbol,
          onChanged: (value) => setState(() => _currencySymbol = value),
        ),
        const SizedBox(height: AppSpacing.xl),
        FulusButton(
          label: 'Finish',
          loading: _submitting,
          onPressed: _submitting ? null : _submitBusiness,
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
