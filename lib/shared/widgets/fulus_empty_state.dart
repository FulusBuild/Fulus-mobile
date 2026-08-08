import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'fulus_button.dart';

/// "No products yet. Add your first product to start selling." —
/// Empty States, Volumes 8/9 of the Visual Design Bible. Renders an
/// icon in place of the Bible's custom illustrations (no illustration
/// assets exist in this codebase yet — see [icon]'s own doc) plus a
/// headline, an optional body line, and at most one action button, per
/// 8.1's "one specific action, or none" rule.
///
/// Copy is entirely the caller's responsibility — 8.1's rules ("never
/// blame the user," "state what's missing, then what happens next,"
/// "reserve alarming words for real problems") are about what
/// [headline]/[body] should say, which only the screen calling this
/// knows. This widget only lays the pattern out consistently, the same
/// way across every screen that needs it.
class FulusEmptyState extends StatelessWidget {
  const FulusEmptyState({
    super.key,
    required this.headline,
    this.body,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.inbox_outlined,
  });

  final String headline;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Material icon standing in for this state's Bible illustration
  /// (Volume 9's "Seven Contexts" figure) until real illustration
  /// assets exist in this codebase.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSize.hero, color: AppColors.textSecondaryOf(context)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
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
