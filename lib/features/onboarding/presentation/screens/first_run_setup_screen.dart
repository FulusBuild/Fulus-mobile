import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';

/// A lightweight handoff after business creation. Nothing on this screen is
/// required: the owner can start selling immediately. Products, printers and
/// cloud are discovered later when they become useful.
class FirstRunSetupScreen extends ConsumerWidget {
  const FirstRunSetupScreen({super.key});

  Future<void> _finish(BuildContext context, WidgetRef ref, {String? routeName}) async {
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.check_circle_outline,
                color: AppColors.primaryOf(context),
                size: AppIconSize.hero,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                "You're ready to sell.",
                textAlign: TextAlign.center,
                style: AppTypography.display.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fulus saves your work on this device, even without internet. You can add products and connect Cloud whenever you’re ready.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.xxl),
              FulusButton(
                label: 'Make a sale',
                onPressed: () => _finish(context, ref, routeName: 'sell'),
              ),
              const SizedBox(height: AppSpacing.md),
              FulusButton(
                label: 'Go to Home',
                variant: FulusButtonVariant.text,
                onPressed: () => _finish(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
