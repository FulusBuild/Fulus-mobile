import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/onboarding_step_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_art.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/onboarding_intro_panel.dart';

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
                const OnboardingStepHeader(
                  step: 5,
                  total: 7,
                  title: 'Make a sale',
                ),
                const OnboardingIntroPanel(
                  icon: Icons.point_of_sale_rounded,
                  eyebrow: 'Your first sale',
                  title: 'See Fulus in action',
                  description:
                      'Open Sell to choose products and complete a sale. You can add products from Stock whenever you need them.',
                ),
                const SizedBox(height: AppSpacing.xl),
                FulusActionTile(
                  icon: FulusIcons.sell,
                  art: FulusArt.sell,
                  label: 'Open Sell',
                  subtitle:
                      'Review your products and start when you are ready.',
                  onTap: () {
                    ref.read(firstSaleIntroSeenProvider.notifier).state = true;
                    context.goNamed('sell');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
