import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Compact, tappable filter/category chip — Component Library 5.2.
/// "Never used for status or alerts — those stay in Warning/Error."
/// Selected state never relies on color alone: fill + border + a
/// leading checkmark together.
///
/// Responsive UI audit — sized by padding around [label] rather than a
/// fixed `height: 36`. A fixed height and dynamic text (larger system
/// font, a longer localized label) don't agree with each other: the
/// container doesn't grow, so it either clips the text or paints it
/// outside its own bounds. Padding lets the chip grow with its content
/// instead. The padding below reproduces the old 36dp almost exactly at
/// default text scale (`AppTypography.label`'s ~19.6dp line height plus
/// [AppSpacing.sm] on each side ≈ 36dp) — same look normally, safe
/// beyond it.
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
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
///
/// Responsive UI audit — used to be a `SizedBox(height: 36)` around a
/// horizontal [ListView]; now an [IntrinsicHeight] row inside a
/// [SingleChildScrollView], so the row's height comes from the chips'
/// own (now content-driven, see [FulusChip]) height instead of a second
/// hardcoded number that would fall out of sync with it. Every call
/// site passes a short, known set of filter chips — never a lazily
/// loaded list — so giving up [ListView]'s virtualization here costs
/// nothing.
class FulusChipRow extends StatelessWidget {
  const FulusChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Redesign pass addition — a small dot-plus-label pill for a passive
/// status, not a tappable filter. Distinct from [FulusChip] on purpose:
/// 5.2 is explicit chips are "never used for status or alerts" — this
/// is the widget that *is* for status (Home's "Synced"/"Offline",
/// Settings' role labels), so the two don't get conflated at a call
/// site. No `onTap` — a status pill only ever reports state.
enum FulusStatusTone { positive, neutral, warning }

class FulusStatusPill extends StatelessWidget {
  const FulusStatusPill({super.key, required this.label, this.tone = FulusStatusTone.positive, this.icon});

  final String label;
  final FulusStatusTone tone;

  /// Optional leading icon in place of the default dot — e.g. a cloud
  /// glyph for sync state.
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
    // Responsive UI audit — padding instead of a fixed `height: 28`,
    // same reasoning as FulusChip just above: AppTypography.label's
    // ~19.6dp line height plus AppSpacing.xs on each side ≈ 28dp at
    // default text scale, so this looks identical normally and only
    // grows if the text actually needs to.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
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
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTypography.label.copyWith(color: color, letterSpacing: 0.2)),
        ],
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
