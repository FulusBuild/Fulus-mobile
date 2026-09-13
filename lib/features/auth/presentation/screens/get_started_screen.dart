import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import 'backup_restore_decision_screen.dart';
import 'cloud_restore_screen.dart';
import 'owner_setup_screen.dart';

/// First-launch entry point for a device with no local owner/business yet.
///
/// The first decision stays deliberately small: create a local business,
/// recover an existing Fulus account, or restore a backup. No network is
/// required to start working.
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
                  Container(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      boxShadow: AppElevation.liftOf(context),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.neutral0.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(AppColors.neutral0, BlendMode.srcIn),
                            child: Image.asset('assets/branding/fulus_mark_transparent.png'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        Text(
                          'Fulus',
                          style: AppTypography.display.copyWith(color: AppColors.neutral0),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Run your business. Simply.',
                          style: AppTypography.title.copyWith(color: AppColors.neutral0),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Sales, stock, and money — ready when you are, even without internet.',
                          style: AppTypography.body.copyWith(color: AppColors.darkTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FulusButton(
                    label: 'Create my business',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      final onboardingState = ref.read(onboardingStateProvider);
                      await onboardingState.advanceWalkthroughTo(OnboardingStep.businessSetup);
                      ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.businessSetup;
                      if (!context.mounted) return;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const OwnerSetupScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusButton(
                    label: 'I already use Fulus',
                    variant: FulusButtonVariant.secondary,
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const CloudRestoreScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusButton(
                    label: 'Restore a backup',
                    variant: FulusButtonVariant.text,
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const BackupRestoreDecisionScreen()),
                      );
                    },
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
