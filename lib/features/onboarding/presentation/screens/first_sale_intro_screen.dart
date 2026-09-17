import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_icons.dart';
import '../../../../shared/widgets/widgets.dart';

/// Walkthrough Phases 6–9 (prep, cart, payment, success) share one
/// resume point — [OnboardingStep.firstSale], see that enum's own doc
/// comment for why. This screen is only the brief transition into that
/// span: "You've created your first product. Now let's sell it." per
/// the spec's own wording. What comes after is the real Sell -> Cart ->
/// Payment flow, completely unmodified — no teaching overlay, no coach
/// marks layered on top of live money-handling screens. The concepts
/// those screens teach (quantity, price, cart total, payment method,
/// change) are taught by using them for real, not by a tutorial
/// describing them first.
///
/// Shown once per app session (see [firstSaleIntroSeenProvider]) —
/// _ShellGate shows the real shell directly once dismissed, and the
/// user finds Sell themselves, having just been shown where it is in
/// the navigation-intro step before this one.
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
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryOf(context).withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(FulusIcons.sell, color: AppColors.primaryOf(context), size: AppIconSize.emphasis),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  "You've created your first product.",
                  style: AppTypography.title.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Now let's sell it. Head to Sell, add it to the cart, and take payment — "
                  'exactly like a real sale, because it is one.',
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
