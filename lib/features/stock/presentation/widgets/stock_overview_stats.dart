import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';

/// "What do I have? How much is it worth? What is running low?" — the
/// task's own three questions, answered in one glanceable row before
/// anything else on the Stock screen. Four [FulusStatCard]s (5.17):
/// Stock Value, Products, Low Stock, Out of Stock. Low Stock and Out of
/// Stock are tappable — they're really shortcuts into the same product
/// list below with a filter pre-applied, not just numbers to look at.
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

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.7,
      children: [
        FulusStatCard(
          label: 'Stock value',
          value: formatMoney(value, compact: true),
          icon: Icons.payments_outlined,
        ),
        FulusStatCard(
          label: 'Products',
          value: '${products.length}',
          icon: Icons.inventory_2_outlined,
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
      ],
    );
  }
}
