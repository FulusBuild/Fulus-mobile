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
    return Semantics(
      button: true,
      label: label,
      child: FulusPressable(
        onPressed: onTap,
        semanticsLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: fulusMotionDuration(context, AppMotion.fast),
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.isDark(context) ? AppColors.surfaceAltDark : AppColors.neutral100,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: AppIconSize.base, color: primary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.visible,
                style: AppTypography.label.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
