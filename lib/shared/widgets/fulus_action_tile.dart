import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';
import '../../core/theme/fulus_icons.dart';

/// A primary Fulus workspace tile.
///
/// This is intentionally more visual than a list row or compact shortcut:
/// large touch area, strong icon, short label, and a quiet surface. Screens
/// should use this for high-value actions that belong in the main workspace.
class FulusActionTile extends StatelessWidget {
  const FulusActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final foreground = AppColors.textPrimaryOf(context);
    final muted = AppColors.textSecondaryOf(context);

    return FulusPressable(
      onPressed: onTap,
      semanticsLabel: subtitle == null ? label : '$label. $subtitle',
      child: Container(
          constraints: const BoxConstraints(minHeight: 120, minWidth: 0),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.75)),
            boxShadow: AppElevation.cardOf(context),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.selectedTintOf(context),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSize.emphasis, color: primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!
              else if (onTap != null)
                Icon(FulusIcons.chevronRight, size: AppIconSize.compact, color: muted),
            ],
          ),
        ),
      );
  }
}
