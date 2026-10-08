import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/theme/fulus_icons.dart';
import '../../core/theme/fulus_art.dart';
import '../../core/ux/consumer_polish.dart';

/// Shared content surface. Cards stay quiet; hierarchy comes from spacing,
/// typography and interaction rather than heavy borders.
class FulusCard extends StatelessWidget {
  const FulusCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.outlined = false,
    this.elevated = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool outlined;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    final borderColor = AppColors.borderOf(context).withValues(alpha: outlined ? 0.9 : 0.65);
    return Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: radius,
          border: outlined ? Border.all(color: borderColor) : null,
          boxShadow: elevated ? AppElevation.cardOf(context) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: DefaultTextStyle.merge(
            style: AppTypography.body.copyWith(
              color: AppColors.isDark(context)
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimaryLight,
            ),
            child: FulusPressable(
              onPressed: onTap,
              child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouchTarget.minimum),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

enum FulusTrend { up, down }

class FulusStatCard extends StatelessWidget {
  const FulusStatCard({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.trendLabel,
    this.valueColor,
    this.icon,
    this.art,
    this.iconColor,
    this.onTap,
  });

  final String label;
  final String value;
  final FulusTrend? trend;
  final String? trendLabel;
  final Color? valueColor;
  final IconData? icon;
  final FulusArt? art;
  final Color? iconColor;
  final VoidCallback? onTap;
  static const minWidth = 136.0;
  static const contentAspectRatio = 1.6;

  @override
  Widget build(BuildContext context) {
    final dataColor = valueColor ?? AppColors.textPrimaryOf(context);

    Widget buildContent({required bool hasFiniteIconRegion}) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: hasFiniteIconRegion ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if ((icon != null || art != null) && hasFiniteIconRegion)
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  child: art != null
                      ? FulusArtIcon(art!, size: AppIconSize.emphasis, semanticLabel: label)
                      : Icon(icon, color: iconColor ?? dataColor),
                ),
              ),
            )
          else if (icon != null || art != null) ...[
            FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              child: art != null
                  ? FulusArtIcon(art!, size: AppIconSize.emphasis, semanticLabel: label)
                  : Icon(icon, color: iconColor ?? dataColor),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTypography.mono.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: dataColor,
              ),
            ),
          ),
          if (trend != null && trendLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trend == FulusTrend.up
                      ? FulusIcons.arrowUp
                      : FulusIcons.arrowDown,
                  size: 20,
                  color: AppColors.mutedOf(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    trendLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      fontSize: 16,
                      color: AppColors.mutedOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );

      if (icon == null && art == null || !hasFiniteIconRegion) return content;

      return AspectRatio(
        // The stat-card family owns the overall content geometry. The
        // prominent icon receives the remaining vertical space after the
        // label/value/trend composition has been laid out.
        aspectRatio: contentAspectRatio,
        child: content,
      );
    }

    return FulusCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: minWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return buildContent(
              hasFiniteIconRegion: constraints.hasBoundedHeight,
            );
          },
        ),
      ),
    );
  }
}

class FulusStatGrid extends StatelessWidget {
  const FulusStatGrid({super.key, required this.cards, this.minTileWidth = FulusStatCard.minWidth + AppSpacing.xl, this.spacing = AppSpacing.md});
  final List<Widget> cards;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : minTileWidth;
        final columns = FulusLayout.columns(availableWidth, minTileWidth: minTileWidth, maxColumns: 4).clamp(1, cards.length);
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          final rowCards = cards.skip(i).take(columns).toList();
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: spacing),
                  Expanded(child: j < rowCards.length ? rowCards[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }
}
