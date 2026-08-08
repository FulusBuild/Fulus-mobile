import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Compact, tappable filter/category chip — Component Library 5.2.
/// "Never used for status or alerts — those stay in Warning/Error."
/// Selected state never relies on color alone: fill + border + a
/// leading checkmark together.
class FulusChip extends StatelessWidget {
  const FulusChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.selectedTintOf(context) : AppColors.surfaceAltOf(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? primary : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: AppIconSize.dense, color: primary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: AppTypography.label.copyWith(color: selected ? primary : AppColors.textPrimaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of [FulusChip]s that scrolls horizontally rather than wraps —
/// "wrapping pushes content below the fold unpredictably on a short
/// screen" (5.2, Overflow).
class FulusChipRow extends StatelessWidget {
  const FulusChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => children[i],
      ),
    );
  }
}

/// Numeric count badge — Component Library 5.10. Caps at "99+", never
/// truncates to something ambiguous.
class FulusBadge extends StatelessWidget {
  const FulusBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.errorOf(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.errorOnOf(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}
