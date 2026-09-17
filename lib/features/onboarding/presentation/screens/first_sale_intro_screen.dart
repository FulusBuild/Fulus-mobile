import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// Walkthrough Phases 6–9 (prep, cart, payment, success) share one
/// resume point — [OnboardingStep.firstSale]. This screen is only the brief
/// transition into that span: the real Sell -> Cart -> Payment flow remains
/// unchanged and teaches those concepts through actual use.
class FirstSaleIntroScreen extends ConsumerWidget {
  const FirstSaleIntroScreen({super.key});

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
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primaryOf(context).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(FulusIcons.sell, color: AppColors.primaryOf(context), size: 32),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  "You've created your first product.",
                  textAlign: TextAlign.center,
                  style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Now let's sell it. Head to Sell, add it to the cart, and take payment — "
                  'exactly like a real sale, because it is one.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusButton(
                  label: "Let's go",
                  icon: FulusIcons.sell,
                  onPressed: () => ref.read(firstSaleIntroSeenProvider.notifier).state = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
