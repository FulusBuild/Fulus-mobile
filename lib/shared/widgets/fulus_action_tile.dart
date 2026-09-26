import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';

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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final foreground = AppColors.textPrimaryOf(context);
    final muted = AppColors.textSecondaryOf(context);

    return Semantics(
      button: true,
      label: subtitle == null ? label : '$label. $subtitle',
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.selectedTintOf(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: AppIconSize.large, color: primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: AppIconSize.compact, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
