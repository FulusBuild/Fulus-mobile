import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';

/// Compact shortcut inspired by modern mobile navigation: a quiet icon
/// treatment, strong label hierarchy and a generous touch target. It reads
/// as a way to move through the product, not as a collection of mini cards.
class FulusQuickAction extends StatelessWidget {
  const FulusQuickAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final textColor = AppColors.textPrimaryOf(context);
    return Semantics(
      button: true,
      label: label,
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Scale the decorative icon with the tile's available width,
              // while keeping the interaction target independent and at
              // least 48dp. This follows the shared responsive grid rather
              // than the physical device type.
              final iconSize = (constraints.maxWidth * .32).clamp(40.0, 48.0).toDouble();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: fulusMotionDuration(context, AppMotion.fast),
                    width: iconSize,
                    height: iconSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.isDark(context) ? AppColors.surfaceAltDark : AppColors.neutral100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: AppIconSize.base, color: primary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: AppTypography.label.copyWith(color: textColor),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
