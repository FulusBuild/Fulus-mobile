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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final FulusArt? art;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.textPrimaryOf(context);
    final color = iconColor ?? AppColors.primaryOf(context);

    return FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
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
              art != null
                  ? FulusArtIcon(art!, size: 30, semanticLabel: label)
                  : Icon(icon, size: 30, color: color),
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
    );
  }
}
