import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_art.dart';
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
    this.trailing,
    this.art,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;
  final FulusArt? art;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final foreground = AppColors.textPrimaryOf(context);

    return FulusPressable(
      onPressed: onTap,
      semanticsLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 128),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.selectedTintOf(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            art != null
                ? FulusArtIcon(art!, size: AppIconSize.emphasis, semanticLabel: label)
                : Icon(icon, size: AppIconSize.emphasis, color: primary),
            Row(
              children: [
                Expanded(
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
                if (trailing != null) trailing!,
              ],
            ),
          ],
        ),
      ),
    );
  }}
