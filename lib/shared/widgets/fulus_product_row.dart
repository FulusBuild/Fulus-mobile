import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatting.dart';
import '../../domain/entities/product.dart';
import 'fulus_card.dart';
import 'fulus_icon_button.dart';
import 'fulus_pressable.dart';

/// Compact product presentation for transactional catalog surfaces.
///
/// The row keeps the product image and commercial information visually quiet,
/// while making the primary add action immediately discoverable.
class FulusProductRow extends StatelessWidget {
  const FulusProductRow({
    super.key,
    required this.productWithStock,
    required this.currencySymbol,
    required this.isFavorite,
    required this.onAdd,
    required this.onToggleFavorite,
    this.showFavorite = true,
  });

  final ProductWithStock productWithStock;
  final String currencySymbol;
  final bool isFavorite;
  final VoidCallback onAdd;
  final VoidCallback onToggleFavorite;
  final bool showFavorite;

  bool get _outOfStock =>
      productWithStock.product.tracksStock && productWithStock.currentStock <= 0;

  @override
  Widget build(BuildContext context) {
    final product = productWithStock.product;
    final primary = AppColors.primaryOf(context);

    return Opacity(
      opacity: _outOfStock ? AppOpacity.disabled : 1,
      child: FulusCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        child: FulusPressable(
          semanticsLabel: _outOfStock
              ? '${product.name}, out of stock'
              : 'Add ${product.name} to sale',
          onPressed: _outOfStock ? null : onAdd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _ProductImage(product: product),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(product.sellingPrice, symbol: currencySymbol),
                        style: AppTypography.body.copyWith(
                          color: primary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _stockLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: _outOfStock
                              ? AppColors.errorOf(context)
                              : product.tracksStock && productWithStock.isLowStock
                                  ? AppColors.warningOf(context)
                                  : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (showFavorite)
                  FulusIconButton(
                    icon: isFavorite ? Icons.star : Icons.star_border,
                    tooltip: isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    onPressed: onToggleFavorite,
                  ),
                const SizedBox(width: AppSpacing.xs),
                _AddButton(enabled: !_outOfStock, onPressed: onAdd),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _stockLabel {
    final product = productWithStock.product;
    if (_outOfStock) return 'Out of stock';
    if (product.tracksStock && productWithStock.isLowStock) {
      return 'Only ${productWithStock.currentStock} left';
    }
    return product.sku.isEmpty ? 'Ready to sell' : 'SKU ${product.sku}';
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 64,
        height: 64,
        color: AppColors.selectedTintOf(context),
        alignment: Alignment.center,
        child: product.photoPath == null
            ? Icon(
                Icons.inventory_2_outlined,
                size: AppIconSize.emphasis,
                color: AppColors.primaryOf(context).withValues(alpha: .55),
              )
            : Image.file(
                File(product.photoPath!),
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.inventory_2_outlined,
                  size: AppIconSize.emphasis,
                  color: AppColors.primaryOf(context).withValues(alpha: .55),
                ),
              ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.primaryOf(context)
          : AppColors.surfaceAltOf(context),
      shape: const CircleBorder(),
      child: FulusPressable(
        semanticsLabel: enabled ? 'Add product' : 'Product unavailable',
        onPressed: enabled ? onPressed : null,
        child: SizedBox(
          width: AppTouchTarget.minimum,
          height: AppTouchTarget.minimum,
          child: Icon(
            Icons.add,
            size: AppIconSize.compact,
            color: enabled
                ? AppColors.onPrimaryOf(context)
                : AppColors.textSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}
