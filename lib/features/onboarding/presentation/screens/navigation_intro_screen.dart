import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/onboarding/onboarding_state.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Walkthrough Phase 5. One static screen, not a coach-mark tour over
/// the running app — matches the spec's own visual-design guidance
/// against tutorial popups covering the UI. Describes the app's real
/// four-tab shell (app_shell.dart: Home, Stock, Sell, Money) plus More,
/// not the spec's own six-item illustrative list — Customers and
/// Reports live under More here, not as separate tabs, and this screen
/// says so rather than describing navigation that doesn't exist.
class NavigationIntroScreen extends ConsumerWidget {
  const NavigationIntroScreen({super.key});

  static const _destinations = [
    _NavDestination(Icons.home_outlined, 'Home', 'See how your business is doing at a glance.'),
    _NavDestination(Icons.inventory_2_outlined, 'Stock', 'Manage your products and stock levels.'),
    _NavDestination(Icons.point_of_sale, 'Sell', 'Make sales and take payment.'),
    _NavDestination(
      Icons.account_balance_wallet_outlined,
      'Money',
      'Track cash and money moving in and out.',
    ),
    _NavDestination(
      Icons.more_horiz,
      'More',
      'Everything else — customers, reports, employees, settings, and backup.',
    ),
  ];

  Future<void> _continue(WidgetRef ref) async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.advanceWalkthroughTo(OnboardingStep.firstSale);
    ref.read(walkthroughStepProvider.notifier).state = OnboardingStep.firstSale;
  }

  Future<void> _skip(WidgetRef ref) async {
    final onboardingState = ref.read(onboardingStateProvider);
    await onboardingState.skipWalkthroughStep(OnboardingStep.navigationIntro);
    await _continue(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Getting around Fulus',
                  style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final destination in _destinations) ...[
                  _DestinationRow(destination: destination),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.md),
                FulusActionTile(
                  icon: FulusIcons.check,
                  label: 'Got it',
                  subtitle: 'Continue to your first sale.',
                  onTap: () => _continue(ref),
                ),
                const SizedBox(height: AppSpacing.md),
                FulusActionTile(
                  icon: Icons.skip_next_rounded,
                  label: 'Skip walkthrough',
                  subtitle: 'You can explore Fulus on your own.',
                  onTap: () => _skip(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination(this.icon, this.label, this.description);

  final IconData icon;
  final String label;
  final String description;
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.destination});

  final _NavDestination destination;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(destination.icon, color: AppColors.primaryOf(context), size: AppIconSize.base),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                destination.label,
                style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
              Text(
                destination.description,
                style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
