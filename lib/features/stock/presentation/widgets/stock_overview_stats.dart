import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';

/// "What do I have? How much is it worth? What is running low?" — the
/// task's own three questions, answered in one glanceable row before
/// anything else on the Stock screen. Four [FulusStatCard]s (5.17):
/// Stock Value, Low Stock, Out of Stock, Products. The two risk states
/// are tappable — they're really shortcuts into the same product list
/// below with a filter pre-applied, not just numbers to look at.
///
/// The order is deliberate: value first, then the two inventory-health
/// exceptions, then total catalogue size. A shopkeeper scanning Stock
/// should see what needs attention before a descriptive count.
///
/// Redesign pass — was a hand-rolled `_compact()` + `_TappableStat`
/// wrapper; both are now shared, reusable pieces instead: compacting
/// goes through `formatMoney(..., compact: true)` (core/utils/
/// formatting.dart), and tappability is [FulusStatCard]'s own new
/// `onTap`. Real bug fix along the way: the old `_compact` only had a
/// "≥ 1,000,000 → M" branch, so a stock value in the billions rendered
/// as e.g. "₦44000.00M" (44,000 million, never reduced further) rather
/// than "₦44.0B" — visible on this exact screen in the reference
/// screenshots. `formatMoney`'s compact form has a proper B tier.
///
/// Responsive UI audit — the 2-column `GridView.count(childAspectRatio:
/// 1.7)` this used is exactly what produced this screen's "BOTTOM
/// OVERFLOWED BY 23 PIXELS" report: an aspect ratio fixes each card's
/// height from the grid's *width* alone, so a narrower device, a longer
/// label wrapping to a second line, or larger system text all grow the
/// card's real content past a cell height that never moves. Swapped for
/// [FulusStatGrid] (shared/widgets/fulus_card.dart), which measures
/// each row's height from its own cards instead of guessing it from
/// width — see that widget's doc comment for the full reasoning.
class StockOverviewStats extends StatelessWidget {
  const StockOverviewStats({
    super.key,
    required this.products,
    required this.onTapLowStock,
    required this.onTapOutOfStock,
  });

  final List<ProductWithStock> products;
  final VoidCallback onTapLowStock;
  final VoidCallback onTapOutOfStock;

  @override
  Widget build(BuildContext context) {
    final value = totalStockValue(products);
    final lowStockCount = products.where((p) => p.isLowStock).length;
    final outOfStock = outOfStockCount(products);

    return FulusStatGrid(
      cards: [
        FulusStatCard(
          label: 'Stock value',
          value: formatMoney(value, compact: true),
          icon: Icons.payments_outlined,
        ),
        FulusStatCard(
          label: 'Low stock',
          value: '$lowStockCount',
          icon: Icons.trending_down,
          valueColor: lowStockCount > 0 ? AppColors.warningOf(context) : null,
          onTap: onTapLowStock,
        ),
        FulusStatCard(
          label: 'Out of stock',
          value: '$outOfStock',
          icon: Icons.remove_shopping_cart_outlined,
          valueColor: outOfStock > 0 ? AppColors.errorOf(context) : null,
          onTap: onTapOutOfStock,
        ),
        FulusStatCard(
          label: 'Products',
          value: '${products.length}',
          icon: Icons.inventory_2_outlined,
        ),
      ],
    );
  }
}
