import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';

/// Canonical tile for a high-value workspace action.
/// Keep the hierarchy identical everywhere: icon top-left, label bottom-left.
class FulusActionTile extends StatelessWidget {
  const FulusActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.accent,
    this.flat = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  /// Kept for source compatibility. The tile-first system intentionally does
  /// not render subtitles inside action tiles.
  final String? subtitle;
  final Widget? trailing;
  final Color? accent;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primaryOf(context);
    final foreground = AppColors.textPrimaryOf(context);

    return FulusPressable(
      onPressed: onTap,
      semanticsLabel: subtitle == null ? label : '$label. $subtitle',
      child: Container(
        constraints: const BoxConstraints(minHeight: 112, minWidth: 0),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: flat ? AppColors.surfaceOf(context) : color.withValues(alpha: 0.12),
          border: flat ? Border.all(color: AppColors.borderOf(context)) : null,
          borderRadius: BorderRadius.circular(flat ? 0 : AppRadius.lg),
        ),
        child: flat
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: AppIconSize.base, color: color),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Icon(icon, size: AppIconSize.emphasis, color: color),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 32),
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Align(alignment: Alignment.topRight, child: trailing!),
                ],
              ),
      ),
    );
  }
}
