import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/fulus_art.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';

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
          value: formatMoney(value),
          icon: FulusIcons.cash,
          art: FulusArt.cash,
        ),
        FulusStatCard(
          label: 'Low stock',
          value: '$lowStockCount',
          icon: FulusIcons.stockIn,
          art: FulusArt.lowStock,
          valueColor: lowStockCount > 0 ? AppColors.warningOf(context) : null,
          onTap: onTapLowStock,
        ),
        FulusStatCard(
          label: 'Out of stock',
          value: '$outOfStock',
          icon: FulusIcons.removeShoppingCart,
          valueColor: outOfStock > 0 ? AppColors.errorOf(context) : null,
          onTap: onTapOutOfStock,
        ),
        FulusStatCard(
          label: 'Products',
          value: '${products.length}',
          icon: FulusIcons.stock,
          art: FulusArt.stock,
        ),
      ],
    );
  }
}
