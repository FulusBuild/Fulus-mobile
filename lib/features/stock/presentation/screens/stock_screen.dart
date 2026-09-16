import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../widgets/product_list_tile.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  late final _searchController = TextEditingController(text: ref.read(stockFilterProvider).query);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(currentLocationIdProvider);
    return FulusScreen(
      title: 'Stock',
      applyPadding: false,
      actions: [
        FulusIconButton(icon: FulusIcons.category, tooltip: 'Categories', onPressed: () => context.pushNamed('stockCategories')),
        FulusIconButton(icon: FulusIcons.upload, tooltip: 'Bulk import', onPressed: () => context.pushNamed('stockBulkImport')),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed('stockRecordMovement'),
        icon: const Icon(FulusIcons.arrowUp),
        label: const Text('Record stock'),
      ),
      body: locationAsync.when(
        loading: () => const FulusLoadingIndicator(),
        error: (error, _) => FulusErrorState(
          message: "Couldn't load Stock.",
          reassurance: 'Nothing here has changed on the device — this is only about loading the view.',
          onRetry: () => ref.invalidate(currentLocationIdProvider),
        ),
        data: (locationId) => _StockBody(locationId: locationId, searchController: _searchController),
      ),
    );
  }
}

class _StockBody extends ConsumerWidget {
  const _StockBody({required this.locationId, required this.searchController});
  final String locationId;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsWithStockProvider(locationId));
    final categoriesAsync = ref.watch(categoriesProvider);
    final filter = ref.watch(stockFilterProvider);

    return productsAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxxl),
        children: const [FulusListRowSkeleton(), FulusListRowSkeleton(), FulusListRowSkeleton()],
      ),
      error: (error, _) => FulusErrorState(
        message: "Couldn't load your products.",
        reassurance: 'Nothing in your catalog was changed — this is only about viewing it right now.',
        onRetry: () => ref.invalidate(productsWithStockProvider(locationId)),
      ),
      data: (products) {
        final categories = categoriesAsync.asData?.value ?? const <Category>[];
        final categoryById = {for (final c in categories) c.localId: c};
        final filtered = applyStockFilter(products, filter);

        if (products.isEmpty) {
          return FulusEmptyState(
            headline: 'No products yet.',
            body: 'Add your first product to start tracking stock.',
            actionLabel: 'Add product',
            onAction: () => context.pushNamed('stockAddProduct'),
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                child: FulusSearchField(
                  controller: searchController,
                  hintText: 'Search products, SKU, barcode…',
                  onChanged: (value) => ref.read(stockFilterProvider.notifier).state = filter.copyWith(query: value),
                ),
              ),
            ),
            if (categories.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: FulusChipRow(children: [
                    FulusChip(label: 'All', selected: filter.categoryId == null, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(categoryId: null)),
                    for (final category in categories)
                      FulusChip(label: category.name, selected: filter.categoryId == category.localId, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(categoryId: category.localId)),
                  ]),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: FulusChipRow(children: [
                        FulusChip(label: 'All', selected: !filter.lowStockOnly && !filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: false, outOfStockOnly: false)),
                        FulusChip(label: 'Low stock', selected: filter.lowStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: !filter.lowStockOnly, outOfStockOnly: false)),
                        FulusChip(label: 'Out of stock', selected: filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(outOfStockOnly: !filter.outOfStockOnly, lowStockOnly: false)),
                      ]),
                    ),
                    FulusIconButton(icon: FulusIcons.sort, tooltip: 'Sort', onPressed: () => _showSortSheet(context, ref, filter)),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                child: Text('${filtered.length} products', style: AppTypography.caption.copyWith(color: AppColors.textSecondaryOf(context))),
              ),
            ),
            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: FulusEmptyState(
                  headline: 'Nothing matches.',
                  body: 'Try a different search or clear your filters.',
                  actionLabel: filter.isDefault ? null : 'Clear filters',
                  onAction: filter.isDefault ? null : () {
                    searchController.clear();
                    ref.read(stockFilterProvider.notifier).state = const StockFilterState();
                  },
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return const FulusListDivider();
                    final item = filtered[index ~/ 2];
                    return ProductListTile(
                      item: item,
                      category: item.product.categoryId == null ? null : categoryById[item.product.categoryId],
                      onTap: () => context.pushNamed('stockProductDetail', pathParameters: {'productId': item.product.localId}),
                    );
                  },
                  childCount: filtered.length * 2 - 1,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
          ],
        );
      },
    );
  }

  void _showSortSheet(BuildContext context, WidgetRef ref, StockFilterState filter) {
    showFulusBottomSheet<void>(
      context: context,
      title: 'Sort by',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in StockSortOrder.values)
            FulusListRow(
              title: Text(option.label),
              trailing: filter.sort == option ? Icon(FulusIcons.check, color: AppColors.primaryOf(sheetContext)) : null,
              onTap: () {
                ref.read(stockFilterProvider.notifier).state = filter.copyWith(sort: option);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }
}
