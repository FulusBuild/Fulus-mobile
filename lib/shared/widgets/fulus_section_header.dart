import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A label introducing a group of content on a screen — e.g. "Recent
/// Sales" above a list, "This Week" above a stat-card row. Not one of
/// the Bible's own numbered 5.x components (no single volume defines
/// it), but implied throughout the Screen Gallery wherever a screen
/// groups more than one kind of content — included here so every
/// screen building such a grouping reaches for one widget rather than
/// a bespoke Text+Row per screen.
class FulusSectionHeader extends StatelessWidget {
  const FulusSectionHeader({super.key, required this.title, this.action, this.onActionTap});

  final String title;

  /// e.g. "See all".
  final String? action;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Responsive UI audit — Expanded+ellipsis added. This is a
          // shared component with call sites across the app; most pass
          // a short, fixed [title], but nothing stopped a future (or
          // data-driven) longer one from overflowing against [action]
          // with no way to give.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.subheading.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryOf(context),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!, style: AppTypography.buttonLabel),
            ),
          ],
        ],
      ),
    );
  }
}
