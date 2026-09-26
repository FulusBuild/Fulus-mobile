import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

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
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryOf(context).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(FulusIcons.check, color: AppColors.primaryOf(context), size: 40),
              ),
            ),
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
            FulusActionTile(
              icon: FulusIcons.add,
              label: 'Add more products',
              subtitle: 'Keep building your inventory.',
              onTap: () => _goAndClose(context, 'stockAddProduct'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.stock,
              label: 'Explore inventory',
              subtitle: 'Review your products and stock levels.',
              onTap: () => _goAndClose(context, 'stock'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.reports,
              label: 'View reports',
              subtitle: 'See how your business is performing.',
              onTap: () => _goAndClose(context, 'moreReports'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.customers,
              label: 'Add customers',
              subtitle: 'Keep customer relationships in one place.',
              onTap: () => _goAndClose(context, 'moneyCustomers'),
            ),
            const SizedBox(height: AppSpacing.md),
            FulusActionTile(
              icon: FulusIcons.home,
              label: 'Start using Fulus',
              subtitle: 'Return to your business home.',
              onTap: () => _goAndClose(context, 'home'),
            ),
          ],
        ),
      ),
    );
  }
}
