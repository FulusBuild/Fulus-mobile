import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';
import 'fulus_button.dart';

/// "The request itself failed" — Component Library 5.19, distinct from
/// [FulusEmptyState] (nothing's wrong, there's just nothing there) and
/// distinct from [FulusTextField]'s own `errorText` (bad input).
/// Rendered inline inside whatever section failed — "never a
/// full-screen takeover unless the entire screen's own data failed to
/// load" (5.19) — so this widget doesn't force a Scaffold/full-screen
/// layout itself; wrap it in whatever the caller's section is.
class FulusErrorState extends StatelessWidget {
  const FulusErrorState({super.key, required this.message, this.reassurance, this.onRetry});

  final String message;
  final String? reassurance;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FulusIcons.error, size: AppIconSize.hero, color: AppColors.errorOf(context)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
            if (reassurance != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                reassurance!,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FulusButton(label: 'Retry', onPressed: onRetry, variant: FulusButtonVariant.secondary),
            ],
          ],
        ),
      ),
    );
  }
}
