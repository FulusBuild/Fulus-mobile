import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/ux/consumer_polish.dart';

/// Compact, tappable filter/category chip. Selection is communicated with
/// fill, border and a checkmark rather than colour alone.
class FulusChip extends StatelessWidget {
  const FulusChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primaryOf(context);
    final border = AppColors.borderOf(context);
    final foreground = selected
        ? primary
        : AppColors.textPrimaryOf(context);

    return Semantics(
      button: true,
      enabled: true,
      label: '$label${selected ? ', selected' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: fulusMotionDuration(context, AppMotion.fast),
          curve: AppMotion.curveStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.selectedTintOf(context)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? primary : border.withValues(alpha: 0.8),
              width: selected ? 1.2 : 1,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouchTarget.minimum),
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_rounded,
                  size: AppIconSize.dense,
                  color: primary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: AppTypography.label.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

/// Horizontally scrolling filter row. It intentionally does not wrap so
/// filters never push the primary content unpredictably below the fold.
class FulusChipRow extends StatelessWidget {
  const FulusChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

enum FulusStatusTone { positive, neutral, warning }

class FulusStatusPill extends StatelessWidget {
  const FulusStatusPill({
    super.key,
    required this.label,
    this.tone = FulusStatusTone.positive,
    this.icon,
  });

  final String label;
  final FulusStatusTone tone;
  final IconData? icon;

  Color _color(BuildContext context) {
    switch (tone) {
      case FulusStatusTone.positive:
        return AppColors.primaryOf(context);
      case FulusStatusTone.neutral:
        return AppColors.textSecondaryOf(context);
      case FulusStatusTone.warning:
        return AppColors.warningOf(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: AppIconSize.dense, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.label.copyWith(
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Numeric count badge. Values above 99 are represented as 99+.
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
