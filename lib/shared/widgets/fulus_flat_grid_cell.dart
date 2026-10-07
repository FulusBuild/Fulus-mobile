import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Flat secondary-navigation cell used when a screen has more destinations
/// than its primary workspace tiles.
class FulusFlatGridCell extends StatelessWidget {
  const FulusFlatGridCell({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.textPrimaryOf(context);
    final color = iconColor ?? AppColors.primaryOf(context);

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: label,
      child: Material(
        color: AppColors.surfaceOf(context),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: color),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
