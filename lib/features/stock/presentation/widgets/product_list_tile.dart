import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';

/// One row in the product list — built on [FulusListRow] (5.4), not a
/// bespoke tile, per the foundation's own "don't create feature-specific
/// versions of shared components" rule. [category] is passed in already
/// resolved (rather than this widget looking it up itself) so a list of
/// 5,000 rows doesn't each independently search a category list — the
/// screen resolves categories once and hands each tile its match.
class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.item,
    required this.category,
    required this.onTap,
  });

  final ProductWithStock item;
  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final outOfStock = product.tracksStock && item.currentStock <= 0;

    return FulusListRow(
      onTap: onTap,
      leading: _Thumbnail(name: product.name),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          category?.name ?? 'Uncategorized',
          '₦${product.sellingPrice.toStringAsFixed(0)}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: product.tracksStock
          ? _StockBadge(quantity: item.currentStock, unit: product.unit, isLow: item.isLowStock, isOut: outOfStock)
          : Text('—', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
    );
  }
}

/// Volume 6: "Photo — strongly encouraged" but never required — no
/// photo-picker/camera integration is in scope for this pass (the task
/// list doesn't call for one, and `Product.photoPath` has no upload
/// path to the backend yet regardless — see product.dart's own doc
/// comment). This is the honest placeholder for that gap: the product's
/// own initial, not a generic box icon, so a photo-less catalog still
/// reads as differentiated rows rather than identical gray squares.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.selectedTintOf(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTypography.buttonLabel.copyWith(color: AppColors.primaryOf(context)),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.unit, required this.isLow, required this.isOut});
  final int quantity;
  final String unit;
  final bool isLow;
  final bool isOut;

  @override
  Widget build(BuildContext context) {
    final color = isOut
        ? AppColors.errorOf(context)
        : isLow
            ? AppColors.warningOf(context)
            : AppColors.textPrimaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$quantity',
          style: AppTypography.body.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(unit, style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
      ],
    );
  }
}
