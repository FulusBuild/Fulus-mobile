import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
import '../../application/stock_providers.dart';
import '../widgets/stock_movement_tile.dart';

/// Product detail remains repository-backed and reactive. This pass only
/// refines its workspace presentation and responsive layout.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(currentLocationIdProvider);

    return locationAsync.when(
      loading: () => const _ProductDetailSkeleton(),
      error: (e, _) => FulusScreen(
        body: FulusErrorState(
          message: "Couldn't load this product.",
          reassurance: 'Your local product data is still safe.',
          onRetry: () => ref.invalidate(currentLocationIdProvider),
        ),
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
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';
    final user = ref.watch(sessionProvider);
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const <Permission>{};
    final canManageStock =
        user?.role == AuthRole.owner ||
        permissions.contains(Permission.manageStock);

    return productsAsync.when(
      loading: () => const _ProductDetailSkeleton(),
      error: (e, _) => FulusScreen(
        body: FulusErrorState(
          message: "Couldn't load this product.",
          reassurance: 'Your local product data is still safe.',
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
              icon: FulusIcons.stock,
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
            if (canManageStock)
              FulusIconButton(
                icon: FulusIcons.edit,
                tooltip: 'Edit product',
                onPressed: () => context.pushNamed('stockEditProduct', extra: product),
              ),
          ],
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              final inset = wide ? AppSpacing.lg : AppSpacing.sm;
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.photoPath != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: AspectRatio(
                                aspectRatio: wide ? 3.2 : 2.1,
                                child: (product.photoPath!.startsWith('http://') || product.photoPath!.startsWith('https://'))
                                  ? CachedRemoteImage(
                                      product.photoPath!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        color: AppColors.surfaceAltOf(context),
                                      ),
                                    )
                                  : Image.file(
                                          File(product.photoPath!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: AppColors.surfaceAltOf(context),
                                            alignment: Alignment.center,
                                            child: Icon(FulusIcons.stock, color: AppColors.mutedOf(context), size: 40),
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _PriceAndStockCard(item: item!, category: category, currencySymbol: currencySymbol),
                          const SizedBox(height: AppSpacing.lg),
                          if (canManageStock && product.tracksStock)
                            FulusActionTile(
                              icon: FulusIcons.swap,
                              label: 'Record stock',
                              subtitle: 'Add, remove or adjust this product quantity.',
                              onTap: () => context.pushNamed('stockRecordMovement', extra: product),
                            ),
                          const SizedBox(height: AppSpacing.xl),
                          const FulusSectionHeader(title: 'History'),
                          if (movements.isEmpty)
                            FulusCard(
                              child: FulusEmptyState(
                                headline: 'No activity yet',
                                body: 'Stock movements for this product will show up here.',
                                icon: FulusIcons.history,
                              ),
                            )
                          else
                            FulusCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0; i < movements.length; i++) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                      child: StockMovementTile(movement: movements[i]),
                                    ),
                                    if (i < movements.length - 1) const FulusListDivider(),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PriceAndStockCard extends StatelessWidget {
  const _PriceAndStockCard({required this.item, required this.category, required this.currencySymbol});

  final ProductWithStock item;
  final Category? category;
  final String currencySymbol;

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
              Flexible(
                child: Text(
                  formatMoney(product.sellingPrice, symbol: currencySymbol),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTypography.heading.copyWith(color: AppColors.textPrimaryOf(context)),
                ),
              ),
            ],
          ),
          if (hasMargin) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Margin', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
                Flexible(
                  child: Text(
                    formatMoney(margin, symbol: currencySymbol),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
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
          Flexible(
            child: Text(label, style: AppTypography.body.copyWith(color: AppColors.textSecondaryOf(context))),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}


class _ProductDetailSkeleton extends StatelessWidget {
  const _ProductDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return FulusScreen(
      title: 'Product',
      subtitle: 'Product details and stock activity',
      applyPadding: false,
      body: ListView(
        padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxl),
        children: const [
          FulusSkeletonBox(height: 180, borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg))),
          SizedBox(height: AppSpacing.lg),
          FulusCardSkeleton(),
          SizedBox(height: AppSpacing.lg),
          FulusSkeletonBox(height: 64, borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
          SizedBox(height: AppSpacing.xl),
          FulusSkeletonBox(width: 120, height: 18),
          SizedBox(height: AppSpacing.sm),
          FulusListRowSkeleton(),
          FulusListRowSkeleton(),
          FulusListRowSkeleton(),
        ],
      ),
    );
  }
}
