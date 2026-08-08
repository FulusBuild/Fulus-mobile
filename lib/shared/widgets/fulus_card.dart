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

  @override
  Widget build(BuildContext context) {
    return FulusCard(
      child: ConstrainedBox(
        // "A stat card that's too narrow to read its own number has
        // stopped being useful" — the 130dp floor from 5.17's
        // Row-of-cards rule, applied here as this card's own minimum.
        constraints: const BoxConstraints(minWidth: 130),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
