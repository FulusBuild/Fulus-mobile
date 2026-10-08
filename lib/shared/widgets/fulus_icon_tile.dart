import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_art.dart';
import '../../core/ux/consumer_polish.dart';

/// Compact horizontal destination tile: a tinted circular icon badge followed
/// by a single-line label on a bordered surface.
///
/// The tile fills whatever height its parent gives it (the badge scales to
/// fit), so grids can be sized from the real window height instead of fixed
/// 168dp cells. A null [onTap] renders the tile dimmed and non-interactive.
class FulusIconTile extends StatelessWidget {
  const FulusIconTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.art,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final FulusArt? art;

  /// Accent used to tint the badge (and the icon when [art] is null).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accent = color ?? AppColors.primaryOf(context);
    final tint = AppColors.isDark(context)
        ? accent.withValues(alpha: 0.18)
        : Color.alphaBlend(accent.withValues(alpha: 0.14), Colors.white);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.hasBoundedHeight ? constraints.maxHeight : 64.0;
            final badge = (height - AppSpacing.sm * 2).clamp(40.0, 52.0).toDouble();
            final glyph = badge * 0.6;

            return Material(
              color: AppColors.surfaceOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.7)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: badge,
                      height: badge,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                      child: art != null
                          ? FulusArtIcon(art!, size: glyph, semanticLabel: label)
                          : Icon(icon, size: glyph, color: accent),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
