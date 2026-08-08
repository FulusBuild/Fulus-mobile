import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
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

  /// "Names what failed" — e.g. "Couldn't load this report."
  final String message;

  /// "Reassures what didn't" — e.g. "Your sales data is safe — this is
  /// only about viewing the report right now." Per 5.19: "not filler,
  /// it's the single most anxiety-relevant sentence for an
  /// offline-first product." Optional only because not every failure
  /// has something reassuring to say; supply it whenever one applies.
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
            Icon(Icons.error_outline, size: AppIconSize.hero, color: AppColors.errorOf(context)),
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
              // "Retry button: Secondary, never Primary — a retry is a
              // recovery action, not the screen's main purpose" (5.19).
              FulusButton(label: 'Retry', onPressed: onRetry, variant: FulusButtonVariant.secondary),
            ],
          ],
        ),
      ),
    );
  }
}
