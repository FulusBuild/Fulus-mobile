import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// The base liftable container — Component Library 5.3. "Product and
/// Customer cards are the same base card with different content slots,
/// not separate components," per the Bible, so this widget is
/// deliberately just a styled container plus optional tap handling; the
/// content inside is entirely up to the caller (a feature team builds
/// its own Product/Customer/Supplier card layout as [child] here,
/// rather than a new container widget per card type).
///
/// Uses [AppElevation.cardOf] (a real shadow) rather than a border —
/// "Elevation — Volume 2's shadow token, not a border; borders are
/// reserved for same-plane separators" (5.3). The two screens built
/// before this foundation phase (Home's hero card, Employees' roster
/// tile) each hand-rolled their own `Container`+`BoxDecoration`
/// instead, one of them using a border where this rule calls for a
/// shadow — not touched here (feature-owned files), but this is the
/// version those should converge on.
class FulusCard extends StatelessWidget {
  const FulusCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Radius 12dp — "one step tighter than dialogs/sheets (20dp), so
    // cards read as 'in the layout' rather than 'floating above it.'"
    final radius = BorderRadius.circular(AppRadius.md);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: radius,
        boxShadow: AppElevation.cardOf(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Trend direction for [FulusStatCard] — "Up/down here means the
/// number's direction, not good/bad" (5.17) — this widget only tracks
/// direction and renders a neutral arrow; a screen that cares whether
/// up is good or bad (the Bible's own "Low stock" example) sets
/// [FulusStatCard.valueColor] explicitly instead of relying on trend
/// color to carry that meaning.
enum FulusTrend { up, down }

/// One glanceable, labeled number — Component Library 5.17. "The
/// Reports category shells and any future dashboard summary use this
/// instead of inventing a new 'big number' treatment per screen."
class FulusStatCard extends StatelessWidget {
  const FulusStatCard({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.trendLabel,
    this.valueColor,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  final String label;
  final String value;

  /// Omit entirely when there's no prior period to compare against —
  /// "never shown as '0% vs yesterday,' which implies a real comparison
  /// happened" (5.17). Only rendered when both this and [trendLabel]
  /// are supplied.
  final FulusTrend? trend;
  final String? trendLabel;

  /// Explicit override for screens where up/down does map to good/bad
  /// (e.g. a warn-colored "Low stock" value) — see [FulusTrend] doc.
  final Color? valueColor;

  /// Redesign pass addition — a small icon-in-tint badge above the
  /// label, purely additive (defaults to none, so every existing call
  /// site — Money, Stock — renders exactly as before). Used by Home's
  /// new notice row so "Low stock" / "Pending credit" / "Unsynced" each
  /// carry a recognizable glyph rather than relying on the label text
  /// alone. Defaults [iconColor] to [valueColor] when unset, since the
  /// two usually agree (a warn-colored value gets a warn-colored icon).
  final IconData? icon;
  final Color? iconColor;

  /// Redesign pass addition — also purely additive. [FulusCard] already
  /// supports `onTap`; this just threads it through so a stat tile can
  /// route somewhere (e.g. Home's "Low stock" tile opening Stock) —
  /// unset leaves the card static, matching every pre-existing call
  /// site.
  final VoidCallback? onTap;

  /// "A stat card that's too narrow to read its own number has stopped
  /// being useful" — the 130dp floor from 5.17's Row-of-cards rule.
  /// Named (rather than an inline literal) so [FulusStatGrid] can size
  /// its columns from the same number this card enforces on itself,
  /// instead of the two drifting apart.
  static const minWidth = 130.0;

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: minWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (iconColor ?? valueColor ?? AppColors.primaryOf(context)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: AppIconSize.compact, color: iconColor ?? valueColor ?? AppColors.primaryOf(context)),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: AppTypography.heading.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: valueColor ?? AppColors.textPrimaryOf(context),
              ),
            ),
            if (trend != null && trendLabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    trend == FulusTrend.up ? Icons.arrow_upward : Icons.arrow_downward,
                    size: AppIconSize.dense,
                    color: AppColors.textSecondaryOf(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(trendLabel!, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Responsive UI audit — new shared component. A responsive grid for a
/// small, known-length set of same-family cards — in practice always
/// [FulusStatCard]s. Replaces the `GridView.count(childAspectRatio:
/// ...)` pattern that produced the "BOTTOM OVERFLOWED" reports on Stock
/// and Home: an aspect ratio derives cell *height* purely from the
/// width Flutter happened to hand the grid, with no regard for what the
/// card inside actually needs — a longer label wrapping to a second
/// line, or a larger system font size, both grow the card's real
/// content height while the ratio-derived cell height stays exactly
/// where it was. This grid never guesses a height: each row is
/// measured via [IntrinsicHeight] and every card in it is stretched to
/// match the tallest one ([CrossAxisAlignment.stretch]), so a row is
/// always exactly as tall as its own content needs, on any device, at
/// any text scale, in any language.
///
/// Column count comes from the width [LayoutBuilder] actually hands
/// this widget divided by [minTileWidth] — never a device check — so
/// the same grid naturally goes from 1 column on a narrow phone up
/// through 2, 3, or 4 as real width allows, per the app-wide responsive
/// grid rule. Capped at 4 and at [cards.length] itself, so a handful of
/// cards on a very wide window still fill the row rather than sitting
/// in a few real columns next to empty ones.
///
/// Built on [Row]+[IntrinsicHeight] rather than [GridView] on purpose:
/// this is for a small, eagerly-built set of cards (a handful of
/// stats), never a lazily-loaded list, so there's no virtualization
/// benefit to give up, and a Row is the only one of the two that can
/// size a row's height from its own children's content instead of
/// requiring one supplied from outside.
class FulusStatGrid extends StatelessWidget {
  const FulusStatGrid({
    super.key,
    required this.cards,
    this.minTileWidth = FulusStatCard.minWidth + AppSpacing.xl,
    this.spacing = AppSpacing.sm,
  });

  /// Typically a list of [FulusStatCard]s.
  final List<Widget> cards;

  /// The narrowest a column may get before the grid drops to fewer
  /// columns. Defaults to a bit above [FulusStatCard.minWidth] itself,
  /// so a column change leaves each card comfortably above its own
  /// "too narrow to read" floor rather than landing exactly on it.
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Plain comparisons rather than num.clamp — clamp's return type is
        // num even when called on an int, which would silently turn
        // `columns` below into a num and break the int-typed loop that
        // uses it as a step.
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : minTileWidth;
        final rawColumns = (availableWidth / minTileWidth).floor();
        final byWidth = rawColumns < 1 ? 1 : (rawColumns > 4 ? 4 : rawColumns);
        final columns = byWidth < cards.length ? byWidth : cards.length;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          final rowCards = cards.skip(i).take(columns).toList();
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) SizedBox(width: spacing),
                    Expanded(child: j < rowCards.length ? rowCards[j] : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}
