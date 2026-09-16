import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import 'backup_restore_decision_screen.dart';
import 'cloud_restore_screen.dart';
import 'fulus_account_screen.dart';
import 'owner_setup_screen.dart';

/// First-launch entry point for a device with no local owner/business yet.
///
/// The primary decision is now the Fulus account itself: people who already
/// use Fulus sign in and restore their business, while new users can create
/// their account and business in one journey. Local file backup remains an
/// explicit recovery option for users who have a database backup rather than
/// a Fulus account.
class GetStartedScreen extends ConsumerWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  const Center(
                    child: FulusBrandLogo(
                      size: 72,
                      padding: 10,
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Run your business. Simply.',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Sales, stock, and money — ready when you are, even without internet.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FulusButton(
                    label: 'Create my Fulus account',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      final onboardingState = ref.read(onboardingStateProvider);
                      await onboardingState.advanceWalkthroughTo(OnboardingStep.businessSetup);
                      ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.businessSetup;
                      if (!context.mounted) return;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const FulusAccountScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const FulusAccountScreen()),
                        );
                      },
                      child: const Text('I already have a Fulus account'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const CloudRestoreScreen()),
                        );
                      },
                      child: const Text('Restore my business'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const BackupRestoreDecisionScreen()),
                        );
                      },
                      child: const Text('Restore a local backup'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const OwnerSetupScreen()),
                        );
                      },
                      child: const Text('Continue offline'),
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
