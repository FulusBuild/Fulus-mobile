import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// Editorial content surface used across Fulus. Cards are deliberately
/// quiet: a thin rule establishes the plane, while the smallest possible
/// shadow keeps touchable surfaces legible without turning the app into a
/// dashboard of floating boxes.
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
    final radius = BorderRadius.circular(AppRadius.md);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: radius,
        border: Border.all(color: AppColors.borderOf(context)),
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

enum FulusTrend { up, down }

/// A publication-style metric block: restrained label, prominent data,
/// optional context. Numeric values use tabular figures for clean columns.
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
  final FulusTrend? trend;
  final String? trendLabel;
  final Color? valueColor;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  static const minWidth = 130.0;

  @override
  Widget build(BuildContext context) {
    final dataColor = valueColor ?? AppColors.textPrimaryOf(context);
    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: minWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppIconSize.compact, color: iconColor ?? dataColor),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: AppColors.mutedOf(context)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: AppTypography.mono.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: dataColor,
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
                    color: AppColors.mutedOf(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      trendLabel!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(color: AppColors.mutedOf(context)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Responsive metric layout that sizes rows from content rather than a
/// guessed aspect ratio. This keeps editorial typography intact at larger
/// text scales and on tablets.
class FulusStatGrid extends StatelessWidget {
  const FulusStatGrid({
    super.key,
    required this.cards,
    this.minTileWidth = FulusStatCard.minWidth + AppSpacing.xl,
    this.spacing = AppSpacing.sm,
  });

  final List<Widget> cards;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
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
