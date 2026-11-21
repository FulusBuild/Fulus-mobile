import 'package:flutter/material.dart';
import '../widgets/onboarding_step_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_art.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/onboarding_intro_panel.dart';

/// Walkthrough Phase 11. `walkthroughStep` is already
/// [OnboardingStep.completion] by the time this screen shows —
/// [TransactionVerificationScreen] sets that before pushing here —
/// so this screen has nothing further to persist; it's the landing point,
/// not another step to record.
class CompletionScreen extends ConsumerWidget {
  const CompletionScreen({super.key});

  void _goAndClose(BuildContext context, String routeName) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    context.goNamed(routeName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnboardingStepHeader(
              step: 7,
              total: 7,
              title: 'Your business is ready',
            ),
            const OnboardingIntroPanel(
              icon: Icons.celebration_outlined,
              eyebrow: 'You’re all set',
              title: 'Your business is ready',
              description:
                  'Your setup is complete. Head to Home or choose what you’d like to do next.',
            ),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(
              label: 'Go to Home',
              icon: FulusIcons.home,
              onPressed: () => _goAndClose(context, 'home'),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'KEEP GOING',
              style: AppTypography.caption.copyWith(
                color: AppColors.mutedOf(context),
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusActionTile(
              icon: FulusIcons.add,
              label: 'Add more products',
              subtitle: 'Keep building your inventory.',
              onTap: () => _goAndClose(context, 'stockAddProduct'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.stock,
              art: FulusArt.stock,
              label: 'Explore inventory',
              subtitle: 'Review your products and stock levels.',
              onTap: () => _goAndClose(context, 'stock'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.reports,
              art: FulusArt.reports,
              label: 'View reports',
              subtitle: 'See how your business is performing.',
              onTap: () => _goAndClose(context, 'moreReports'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.customers,
              art: FulusArt.customers,
              label: 'Add customers',
              subtitle: 'Keep customer relationships in one place.',
              onTap: () => _goAndClose(context, 'moneyCustomers'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
