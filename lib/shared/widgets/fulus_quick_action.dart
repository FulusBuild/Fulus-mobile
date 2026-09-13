import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Compact action shortcut. The icon sits on a quiet editorial rule rather
/// than inside a saturated card, so a group of actions reads as navigation,
/// not another dashboard panel.
class FulusQuickAction extends StatelessWidget {
  const FulusQuickAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppTouchTarget.minimum,
                height: AppTouchTarget.minimum,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  border: Border.all(color: AppColors.borderOf(context)),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  size: AppIconSize.base,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
