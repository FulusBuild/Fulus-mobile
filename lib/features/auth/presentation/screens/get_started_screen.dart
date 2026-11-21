import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_art.dart';
import '../../../../shared/widgets/widgets.dart';
import 'fulus_account_screen.dart';
import 'owner_setup_screen.dart';
import 'employee_join_business_screen.dart';
import 'employee_login_screen.dart';
import 'identity_picker_screen.dart';

/// First-launch entry point for a device with no local owner/business yet.
///
/// Cloud restore is part of the login flow on a fresh installation. An
/// already-running local business connects to Cloud from Settings instead;
/// it never restores a cloud business over local data.
class GetStartedScreen extends ConsumerWidget {
  const GetStartedScreen({super.key, this.returningLocalBusiness = false});

  /// Shown after an owner signs out. Their local business stays intact, so
  /// this welcome entry offers a safe way back into it instead of pretending
  /// the device is a fresh installation.
  final bool returningLocalBusiness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
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
                    returningLocalBusiness
                        ? 'Welcome back to Fulus.'
                        : 'Run your business. Simply.',
                    textAlign: TextAlign.center,
                    style: AppTypography.display.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    returningLocalBusiness
                        ? 'Your business is still saved on this device. Continue locally or sign in to restore another business.'
                        : 'Sales, stock, and money — ready when you are, even without internet.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (returningLocalBusiness)
                    FulusActionTile(
                      label: 'Continue on this device',
                      subtitle: 'Your business records stay on this phone.',
                      icon: Icons.storefront_rounded,
                      art: FulusArt.createBusiness,
                      onTap: () => _openEntry(
                        context,
                        ref,
                        const IdentityPickerScreen(),
                      ),
                    )
                  else
                    FulusActionTile(
                      label: 'Create your business',
                      subtitle: 'Set up Fulus in a few simple steps.',
                      icon: Icons.storefront_rounded,
                      art: FulusArt.createBusiness,
                      onTap: () async {
                        final onboardingState = ref.read(
                          onboardingStateProvider,
                        );
                        await onboardingState.advanceWalkthroughTo(
                          OnboardingStep.businessSetup,
                        );
                        ref.read(walkthroughStepProvider.notifier).state =
                            OnboardingStep.businessSetup;
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
                    label: returningLocalBusiness
                        ? 'Sign in or restore'
                        : 'Sign in',
                    subtitle: 'Restore a Fulus business to this device.',
                    icon: Icons.login_rounded,
                    art: FulusArt.signIn,
                    onTap: () =>
                        _openEntry(context, ref, const FulusAccountScreen()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FulusActionTile(
                    label: 'Staff',
                    subtitle: 'Sign in or join a business as an employee.',
                    icon: Icons.badge_outlined,
                    art: FulusArt.joinEmployee,
                    onTap: () => _showStaffChoices(context, ref),
                  ),
                  if (!returningLocalBusiness) ...[
                    const SizedBox(height: AppSpacing.sm),
                    FulusActionTile(
                      label: 'Continue offline',
                      subtitle: 'Run your business locally without an account.',
                      icon: Icons.cloud_off_rounded,
                      art: FulusArt.offline,
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const OwnerSetupScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEntry(
    BuildContext context,
    WidgetRef ref,
    Widget screen,
  ) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => screen));
    if (context.mounted && ref.read(sessionProvider) != null) {
      context.go('/');
    }
  }

  Future<void> _showStaffChoices(BuildContext context, WidgetRef ref) async {
    await showFulusBottomSheet<void>(
      context: context,
      title: 'Staff',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusActionTile(
            icon: Icons.login_rounded,
            art: FulusArt.signIn,
            label: 'Sign in',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openEntry(context, ref, const EmployeeLoginScreen());
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          FulusActionTile(
            icon: Icons.badge_rounded,
            art: FulusArt.joinEmployee,
            label: 'Join a business',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openEntry(context, ref, const EmployeeJoinBusinessScreen());
            },
          ),
        ],
      ),
    );
  }
}
