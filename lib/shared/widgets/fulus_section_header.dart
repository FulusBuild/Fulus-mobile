import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Quiet section heading used to establish hierarchy without adding heavy
/// chrome to feature screens.
class FulusSectionHeader extends StatelessWidget {
  const FulusSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onActionTap,
  });

  final String title;
  final String? action;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.heading.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: AppTypography.buttonLabel.copyWith(color: primary)),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.arrow_forward_rounded, size: AppIconSize.dense),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
