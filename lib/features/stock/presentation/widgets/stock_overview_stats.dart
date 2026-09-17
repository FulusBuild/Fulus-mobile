import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
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
          value: formatMoney(value, compact: true),
          icon: FulusIcons.payments,
        ),
        FulusStatCard(
          label: 'Low stock',
          value: '$lowStockCount',
          icon: FulusIcons.arrowDown,
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
        ),
      ],
    );
  }
}
