import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';

/// Scoped to the onboarding feature, same convention as
/// AuthErrorBanner — not promoted to shared/widgets/, since this
/// styling choice belongs to whichever feature actually needs it.
class OnboardingErrorBanner extends StatelessWidget {
  const OnboardingErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.errorOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: color, size: AppIconSize.compact),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTypography.body.copyWith(color: color))),
        ],
      ),
    );
  }
}
