import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';

/// "What do I have? How much is it worth? What is running low?" — the
/// task's own three questions, answered in one glanceable row before
/// anything else on the Stock screen. Four [FulusStatCard]s (5.17):
/// Stock Value, Products, Low Stock, Out of Stock. Low Stock and Out of
/// Stock are tappable — they're really shortcuts into the same product
/// list below with a filter pre-applied, not just numbers to look at.
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
        FulusStatCard(label: 'Stock value', value: '₦${_compact(value)}'),
        FulusStatCard(label: 'Products', value: '${products.length}'),
        _TappableStat(
          onTap: onTapLowStock,
          child: FulusStatCard(
            label: 'Low stock',
            value: '$lowStockCount',
            valueColor: lowStockCount > 0 ? AppColors.warningOf(context) : null,
          ),
        ),
        _TappableStat(
          onTap: onTapOutOfStock,
          child: FulusStatCard(
            label: 'Out of stock',
            value: '$outOfStock',
            valueColor: outOfStock > 0 ? AppColors.errorOf(context) : null,
          ),
        ),
      ],
    );
  }

  /// ₦48,200 stays as-is; ₦1,284,000 becomes ₦1.28M — a stat card (5.17)
  /// is a glance, not a ledger, and the Bible's own 130dp-minimum-width
  /// rule for these cards means a long, un-compacted number is exactly
  /// what risks getting clipped.
  static String _compact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// [FulusStatCard] has no onTap of its own (5.17 doesn't call for one —
/// most stat cards are look-only) — wrapping rather than adding a
/// tap-specific variant, since only two of the four cards here need it.
class _TappableStat extends StatelessWidget {
  const _TappableStat({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: child,
    );
  }
}
