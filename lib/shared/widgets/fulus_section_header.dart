import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';

/// Quiet section heading used to establish hierarchy without adding heavy
/// chrome to feature screens.
class FulusSectionHeader extends StatelessWidget {
  const FulusSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.titleColor,
    this.subtitleColor,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onActionTap;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final hasAction = action != null && onActionTap != null;
    final stack = hasAction && (MediaQuery.sizeOf(context).width < 360 || textScale > 1.15);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.title.copyWith(
            color: titleColor ?? AppColors.textPrimaryOf(context),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.35,
          ),
        ),

      ],
    );

    final actionButton = !hasAction
        ? null
        : TextButton(
            onPressed: onActionTap,
            style: TextButton.styleFrom(
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(AppTouchTarget.minimum, AppTouchTarget.minimum),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              overlayColor: primary.withValues(alpha: 0.08),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    action!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.buttonLabel.copyWith(color: primary),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(FulusIcons.arrowForward, size: AppIconSize.dense),
              ],
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                if (actionButton != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(alignment: Alignment.centerRight, child: actionButton),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                if (actionButton != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  actionButton,
                ],
              ],
            ),
    );
  }
}
