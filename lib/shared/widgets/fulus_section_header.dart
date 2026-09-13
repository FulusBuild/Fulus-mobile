import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Publication-style section heading shared across feature screens. The
/// heading carries the serif editorial voice; the action stays functional
/// and compact so content, not chrome, remains the visual focus.
class FulusSectionHeader extends StatelessWidget {
  const FulusSectionHeader({super.key, required this.title, this.action, this.onActionTap});

  final String title;
  final String? action;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimaryOf(context),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: AppTypography.buttonLabel),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.arrow_forward, size: AppIconSize.dense),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
