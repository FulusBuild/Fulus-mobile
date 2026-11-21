import 'package:flutter/material.dart';
import '../widgets/onboarding_step_header.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../widgets/onboarding_intro_panel.dart';

/// A lightweight handoff after business creation. Nothing on this screen is
/// required: the owner can start selling immediately. Products, printers and
/// cloud are discovered later when they become useful.
class FirstRunSetupScreen extends ConsumerWidget {
  const FirstRunSetupScreen({super.key});

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref, {
    String? routeName,
  }) async {
    await ref.read(onboardingStateProvider).markFirstRunPromptSeen();
    ref.read(firstRunPromptSeenProvider.notifier).state = true;
    if (!context.mounted) return;
    if (routeName == null) {
      context.go('/');
    } else {
      context.goNamed(routeName);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FulusScreen(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnboardingStepHeader(
                  step: 1,
                  total: 7,
                  title: 'You’re ready to run your business',
                ),
                const OnboardingIntroPanel(
                  icon: Icons.check_rounded,
                  eyebrow: 'Setup complete',
                  title: 'You’re ready to sell',
                  description:
                      'Your work is saved on this device, even without internet. Add products and connect your account whenever you’re ready.',
                ),
                const SizedBox(height: AppSpacing.xxl),
                FulusActionTile(
                  icon: FulusIcons.sell,
                  label: 'Make a sale',
                  subtitle: 'Start selling right away.',
                  onTap: () => _finish(context, ref, routeName: 'sell'),
                ),
                const SizedBox(height: AppSpacing.md),
                FulusActionTile(
                  icon: FulusIcons.home,
                  label: 'Go to Home',
                  subtitle: 'See your business at a glance.',
                  onTap: () => _finish(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
