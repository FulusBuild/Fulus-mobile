import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import 'fulus_account_screen.dart';
import 'owner_setup_screen.dart';

/// First-launch entry point for a device with no local owner/business yet.
///
/// Cloud restore is part of the login flow on a fresh installation. An
/// already-running local business connects to Cloud from Settings instead;
/// it never restores a cloud business over local data.
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
                  FulusActionTile(
                    title: 'Create your business',
                    subtitle: 'Set up Fulus in a few simple steps.',
                    icon: Icons.storefront_rounded,
                    onTap: () async {
                    icon: Icons.arrow_forward_rounded,
                    onTap: () async {
                      final onboardingState = ref.read(onboardingStateProvider);
                      await onboardingState.advanceWalkthroughTo(OnboardingStep.businessSetup);
                      ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.businessSetup;
                      if (!context.mounted) return;
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const FulusAccountScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusActionTile(
                    title: 'Sign in',
                    subtitle: 'Restore a Fulus business to this device.',
                    icon: Icons.login_rounded,
                    onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const FulusAccountScreen(),
                          ),
                        );
                      },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusActionTile(
                    title: 'Continue offline',
                    subtitle: 'Run your business locally without an account.',
                    icon: Icons.cloud_off_rounded,
                    onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const OwnerSetupScreen(),
                          ),
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
