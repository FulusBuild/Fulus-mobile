import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/onboarding_error_banner.dart';
import '../widgets/onboarding_step_header.dart';

/// Walkthrough Phase 3. Deliberately narrow: of everything a business
/// can configure, tax is the one setting that materially changes what
/// the first sale actually records (whether a VAT line appears on the
/// receipt and in Sale.tax at all) — currency and category are already
/// collected in OwnerSetupScreen, and nothing else here would change
/// the outcome of the walkthrough's own first sale. Everything else
/// stays reachable later, normally, through Settings.
class EssentialSettingsScreen extends ConsumerStatefulWidget {
  const EssentialSettingsScreen({super.key});

  @override
  ConsumerState<EssentialSettingsScreen> createState() => _EssentialSettingsScreenState();
}

class _EssentialSettingsScreenState extends ConsumerState<EssentialSettingsScreen> {
  bool _submitting = false;
  String? _bannerMessage;

  Future<void> _advancePastThisStep() async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.advanceWalkthroughTo(OnboardingStep.firstProduct);
    if (!mounted) return;
    ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.firstProduct;
  }

  Future<void> _skip() async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.skipWalkthroughStep(OnboardingStep.essentialSettings);
    if (!mounted) return;
    await _advancePastThisStep();
  }

  Future<void> _save(BusinessProfile current, bool vatEnabled, double vatRate) async {
    setState(() {
      _submitting = true;
      _bannerMessage = null;
    });
    try {
      await ref.read(businessSettingsRepositoryProvider).updateSettings(
            businessName: current.businessName,
            address: current.address,
            phone: current.phone,
            email: current.email,
            tin: current.tin,
            vatEnabled: vatEnabled,
            vatRate: vatRate,
            currencySymbol: current.currencySymbol,
          );
      if (!mounted) return;
      await _advancePastThisStep();
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
      body: StreamBuilder<BusinessProfile?>(
        stream: ref.watch(businessSettingsRepositoryProvider).watchSettings(),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const FulusLoadingIndicator();
          }
          return _EssentialSettingsForm(
            profile: profile,
            submitting: _submitting,
            bannerMessage: _bannerMessage,
            onSave: _save,
            onSkip: _skip,
          );
        },
      ),
    );
  }
}

class _EssentialSettingsForm extends StatefulWidget {
  const _EssentialSettingsForm({
    required this.profile,
    required this.submitting,
    required this.bannerMessage,
    required this.onSave,
    required this.onSkip,
  });

  final BusinessProfile profile;
  final bool submitting;
  final String? bannerMessage;
  final Future<void> Function(BusinessProfile current, bool vatEnabled, double vatRate) onSave;
  final Future<void> Function() onSkip;

  @override
  State<_EssentialSettingsForm> createState() => _EssentialSettingsFormState();
}

class _EssentialSettingsFormState extends State<_EssentialSettingsForm> {
  late bool _vatEnabled = widget.profile.vatEnabled;
  late final _rateController = TextEditingController(text: widget.profile.vatRate.toString());
  String? _rateError;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_vatEnabled) {
      widget.onSave(widget.profile, false, 0);
      return;
    }
    final rate = double.tryParse(_rateController.text.trim());
    if (rate == null || rate < 0) {
      setState(() => _rateError = 'Enter a tax rate of 0 or higher.');
      return;
    }
    setState(() => _rateError = null);
    widget.onSave(widget.profile, true, rate);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const OnboardingStepHeader(step: 2, total: 7, title: 'Essential business settings', subtitle: 'Set the one option that changes how your first sale is recorded.'),
              Text('One more thing', style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This determines whether tax appears on your receipts and sales records from your very first sale. You can change it any time in Settings.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (widget.bannerMessage != null) ...[
                OnboardingErrorBanner(message: widget.bannerMessage!),
                const SizedBox(height: AppSpacing.md),
              ],
              FulusListRow(
                title: const Text('Charge tax on sales'),
                trailing: Switch(
                  value: _vatEnabled,
                  onChanged: (value) => setState(() => _vatEnabled = value),
                ),
                onTap: () => setState(() => _vatEnabled = !_vatEnabled),
              ),
              if (_vatEnabled) ...[
                const SizedBox(height: AppSpacing.md),
                FulusTextField(
                  controller: _rateController,
                  label: 'Tax rate (%)',
                  errorText: _rateError,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FulusButton(
                label: 'Continue',
                loading: widget.submitting,
                onPressed: widget.submitting ? null : _submit,
              ),
              const SizedBox(height: AppSpacing.sm),
              FulusButton(
                label: "I'll set this up later",
                variant: FulusButtonVariant.text,
                onPressed: widget.submitting ? null : widget.onSkip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
