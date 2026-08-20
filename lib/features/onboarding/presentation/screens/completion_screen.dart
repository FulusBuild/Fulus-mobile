import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Walkthrough Phase 11. `walkthroughStep` is already
/// [OnboardingStep.completion] by the time this screen shows —
/// [TransactionVerificationScreen] sets that before pushing here — so
/// this screen has nothing further to persist; it's the landing point,
/// not another step to record. Each next action really navigates
/// there via the same named routes the rest of the app already uses,
/// not a decorative label. `goNamed` alone (no manual pop first) is
/// deliberate — same pattern FirstRunSetupScreen already uses
/// successfully: go_router re-resolves the whole route tree against
/// the new location in one step, discarding this pushed screen and
/// everything under it, without a separate pop that could hit an
/// already-unmounting context.
class CompletionScreen extends ConsumerWidget {
  const CompletionScreen({super.key});

  void _goAndClose(BuildContext context, String routeName) {
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
            Icon(Icons.check_circle_outline, color: AppColors.primaryOf(context), size: 56),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "You're ready to run your business with Fulus.",
              style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your business is set up, your first product is in inventory, and your first '
              'sale has been recorded.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.xl),
            FulusButton(
              label: 'Add more products',
              variant: FulusButtonVariant.secondary,
              onPressed: () => _goAndClose(context, 'stockAddProduct'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusButton(
              label: 'Explore inventory',
              variant: FulusButtonVariant.secondary,
              onPressed: () => _goAndClose(context, 'stock'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusButton(
              label: 'View reports',
              variant: FulusButtonVariant.secondary,
              onPressed: () => _goAndClose(context, 'moreReports'),
            ),
            const SizedBox(height: AppSpacing.sm),
            FulusButton(
              label: 'Add customers',
              variant: FulusButtonVariant.secondary,
              onPressed: () => _goAndClose(context, 'moneyCustomers'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FulusButton(
              label: 'Start using Fulus',
              onPressed: () => _goAndClose(context, 'home'),
            ),
          ],
        ),
      ),
    );
  }
}
