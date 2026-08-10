import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/stock_movement_tile.dart';

/// Volume 6: "Every product's detail screen carries a reverse-
/// chronological history: every sale, stock in/out, transfer, and
/// adjustment, and price change, each with a timestamp and who made
/// it." Two honest gaps against that exact sentence, both flagged
/// rather than invented around: price-change history isn't tracked
/// anywhere in this data model (no movement type for it), and "who"
/// isn't available either ([StockMovementTile]'s own doc comment).
/// Sales show up here for free the moment Sell exists to create them —
/// see stock_providers.dart's own comment on why.
///
/// Watches [productsWithStockProvider] and finds this one product
/// rather than a dedicated single-product fetch, so this screen updates
/// live the moment a stock movement changes this product's count —
/// "reactive by default," the same reasoning [ProductRepository]'s own
/// doc comment gives for why [watchProducts] is a Stream in the first
/// place.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(currentLocationIdProvider);

    return locationAsync.when(
      loading: () => const FulusScreen(body: FulusLoadingIndicator()),
      error: (e, _) => FulusScreen(
        body: FulusErrorState(message: "Couldn't load this product.", onRetry: () => ref.invalidate(currentLocationIdProvider)),
      ),
      data: (locationId) => _ProductDetailBody(productId: productId, locationId: locationId),
    );
  }
}

class _ProductDetailBody extends ConsumerWidget {
  const _ProductDetailBody({required this.productId, required this.locationId});

  final String productId;
  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsWithStockProvider(locationId));
    final categoriesAsync = ref.watch(categoriesProvider);
    final movementsAsync = ref.watch(stockMovementsProvider(locationId));

    return productsAsync.when(
      loading: () => const FulusScreen(body: FulusLoadingIndicator()),
      error: (e, _) => FulusScreen(
        body: FulusErrorState(
          message: "Couldn't load this product.",
          onRetry: () => ref.invalidate(productsWithStockProvider(locationId)),
        ),
      ),
      data: (products) {
        ProductWithStock? item;
        for (final p in products) {
          if (p.product.localId == productId) {
            item = p;
            break;
          }
        }
        if (item == null) {
          return FulusScreen(
            title: 'Product',
            body: FulusEmptyState(
              headline: "This product isn't here anymore.",
              body: 'It may have been removed.',
              icon: Icons.inventory_2_outlined,
            ),
          );
        }

        final product = item.product;
        final categories = categoriesAsync.asData?.value ?? const <Category>[];
        Category? category;
        if (product.categoryId != null) {
          for (final c in categories) {
            if (c.localId == product.categoryId) {
              category = c;
              break;
            }
          }
        }
        final movements = (movementsAsync.asData?.value ?? const [])
            .where((m) => m.productLocalId == productId)
            .toList();

        return FulusScreen(
          title: product.name,
          actions: [
            FulusIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Edit product',
              onPressed: () => context.pushNamed('stockEditProduct', extra: product),
            ),
          ],
          body: ListView(
            children: [
              _PriceAndStockCard(item: item, category: category),
              const SizedBox(height: AppSpacing.lg),
              FulusButton(
                label: 'Record stock',
                icon: Icons.swap_vert,
                onPressed: () => context.pushNamed('stockRecordMovement', extra: product),
              ),
              const SizedBox(height: AppSpacing.xl),
              FulusSectionHeader(title: 'History'),
              if (movements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: FulusEmptyState(
                    headline: 'No activity yet.',
                    body: 'Stock movements for this product will show up here.',
                    icon: Icons.history,
                  ),
                )
              else
                for (final movement in movements) StockMovementTile(movement: movement),
            ],
          ),
        );
      },
    );
  }
}

class _PriceAndStockCard extends StatelessWidget {
  const _PriceAndStockCard({required this.item, required this.category});

  final ProductWithStock item;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    final hasMargin = product.costPrice > 0;
    final margin = product.sellingPrice - product.costPrice;

    return FulusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Price', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              Text(
                '₦${product.sellingPrice.toStringAsFixed(2)}',
                style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ],
          ),
          if (hasMargin) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Margin', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                Text(
                  '₦${margin.toStringAsFixed(2)}',
                  style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ],
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.md), child: Divider(height: 1)),
          _row(context, 'Category', category?.name ?? 'Uncategorized'),
          _row(context, 'In stock', product.tracksStock ? '${item.currentStock} ${product.unit}' : 'Not tracked'),
          if (product.tracksStock) _row(context, 'Low stock at', '${product.lowStockThreshold} ${product.unit}'),
          if (product.barcode != null && product.barcode!.isNotEmpty) _row(context, 'Barcode', product.barcode!),
          _row(context, 'SKU', product.sku),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          Text(value, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context))),
        ],
      ),
    );
  }
}
