import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Redesign pass addition — an icon-in-tint square with a label
/// underneath, for a row of navigation shortcuts (Home's Sell/Add
/// stock/Add expense/Reports row). Deliberately its own widget rather
/// than a repurposed [FulusStatCard]: a stat card shows a *number*
/// (5.17's own words, "one glanceable, labeled number"); this shows an
/// *action*. Conflating the two would make Home's stat row and action
/// row visually indistinguishable, which defeats the point of having
/// both. Full 48dp touch target honored via the tappable square itself
/// plus label, not just the icon glyph.
class FulusQuickAction extends StatelessWidget {
  const FulusQuickAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppTouchTarget.minimum,
              height: AppTouchTarget.minimum,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.selectedTintOf(context),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: AppIconSize.base, color: AppColors.primaryOf(context)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}
