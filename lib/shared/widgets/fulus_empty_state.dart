import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';
import 'fulus_button.dart';

/// "No products yet. Add your first product to start selling." —
/// Empty States, Volumes 8/9 of the Visual Design Bible. Renders an
/// icon in place of the Bible's custom illustrations (no illustration
/// assets exist in this codebase yet — see [icon]'s own doc) plus a
/// headline, an optional body line, and at most one action button, per
/// 8.1's "one specific action, or none" rule.
class FulusEmptyState extends StatelessWidget {
  const FulusEmptyState({
    super.key,
    required this.headline,
    this.body,
    this.actionLabel,
    this.onAction,
    this.icon = FulusIcons.inbox,
  });

  final String headline;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.selectedTintOf(context),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: AppIconSize.hero, color: AppColors.primaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FulusButton(label: actionLabel!, onPressed: onAction, variant: FulusButtonVariant.primary),
            ],
          ],
        ),
      ),
    );
  }
}
