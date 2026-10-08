import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_art.dart';
import '../../core/ux/consumer_polish.dart';

/// Flat secondary-navigation cell used when a screen has more destinations
/// than its primary workspace tiles.
class FulusFlatGridCell extends StatelessWidget {
  const FulusFlatGridCell({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.art,
    this.iconSize = 44,
    this.minHeight = 112,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final FulusArt? art;

  /// Icon edge length. Icons are the primary signal on these cells, so the
  /// default is large; screens with room (More) pass a bigger value.
  final double iconSize;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.textPrimaryOf(context);
    // Artwork is already fully colored; iconColor only applies to the
    // fallback glyph used by utility-grid callers.
    final color = iconColor ?? AppColors.primaryOf(context);

    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: AppColors.dividerOf(context),
                width: 0.5,
              ),
              bottom: BorderSide(
                color: AppColors.dividerOf(context),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The cell's pressable owns the accessible label. Artwork is
              // decorative here so screen readers announce each destination
              // exactly once instead of reading the label twice.
              art != null
                  ? ExcludeSemantics(
                      child: FulusArtIcon(art!, size: iconSize),
                    )
                  : Icon(icon, size: iconSize, color: color),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
