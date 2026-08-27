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
/// not a decorative label.
///
/// FIX (onboarding audit): this screen sits at the bottom of a chain of
/// plain `Navigator.push`/`pushReplacement` calls — SellScreen's cart
/// button -> CartScreen -> PaymentScreen -> SaleSuccessScreen ->
/// TransactionVerificationScreen -> here — none of which are on
/// go_router's own page stack. `goNamed` alone does NOT discard that
/// pushed stack (the earlier comment's assumption was wrong): since
/// go_router 3.0, `go`/`goNamed` only ever reconciles go_router's own
/// declarative pages, leaving any plain-Navigator pushes sitting on top
/// untouched. Every button here silently updated go_router's state
/// while this whole chain stayed on screen, looking frozen. The
/// `popUntil` below unwinds that plain-Navigator chain first (the same
/// pattern SaleSuccessScreen's own "New sale" action already uses
/// successfully), so `goNamed` then has a clean stack to resolve
/// against.
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
