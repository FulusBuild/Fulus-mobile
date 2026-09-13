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
/// New installations can start locally without a network, while returning
/// users who have an existing Fulus Cloud account have an explicit recovery
/// path before they are asked to create a second local business.
class GetStartedScreen extends ConsumerWidget {
  const GetStartedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: Column(
        children: [
          const Spacer(flex: 3),
          _Mark(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Fulus',
            style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Sales, stock, and money — run your shop from your pocket.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const Spacer(flex: 4),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Get started',
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
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'I already have a Fulus account',
              variant: FulusButtonVariant.secondary,
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const CloudRestoreScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: FulusButton(
              label: 'Restore from a backup',
              variant: FulusButtonVariant.text,
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const BackupRestoreDecisionScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.primaryOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Image.asset('assets/branding/fulus_mark_transparent.png'),
    );
  }
}
