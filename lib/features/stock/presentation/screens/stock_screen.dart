import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/category.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../application/stock_providers.dart';
import '../../../money/presentation/providers/money_providers.dart' show moneyCurrencySymbolProvider;
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
      subtitle: 'See what you have and record stock changes',
      applyPadding: false,
      actions: [
        FulusIconButton(
          icon: FulusIcons.add,
          tooltip: 'Add product',
          onPressed: () => context.pushNamed('stockAddProduct'),
        ),
        FulusIconButton(
          icon: FulusIcons.more,
          tooltip: 'More stock options',
          onPressed: () => _showStockActions(context),
        ),
      ],
      floatingActionButton: null,
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

  void _showStockActions(BuildContext context) {
    showFulusBottomSheet<void>(
      context: context,
      title: 'Stock options',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FulusListRow(
            leading: const Icon(FulusIcons.category),
            title: const Text('Categories'),
            subtitle: const Text('Organize and manage product categories'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.pushNamed('stockCategories');
            },
          ),
          FulusListRow(
            leading: const Icon(FulusIcons.upload),
            title: const Text('Import products'),
            subtitle: const Text('Add many products from a file'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.pushNamed('stockBulkImport');
            },
          ),
        ],
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
    final currencySymbol = ref.watch(moneyCurrencySymbolProvider).value ?? '₦';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final contentWidth = width >= 1200 ? 1120.0 : width;
        final inset = width >= 1200 ? ((width - contentWidth) / 2) + AppSpacing.lg : AppSpacing.lg;

        return productsAsync.when(
          loading: () => ListView(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.xxxl),
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
            final trackedProducts = products.where((p) => p.product.tracksStock);
            final totalUnits = trackedProducts.fold<double>(0, (sum, p) => sum + p.currentStock);
            final totalValue = totalStockValue(products);
            final lowStockCount = products.where((p) => p.product.tracksStock && p.isLowStock && p.currentStock > 0).length;
            final outOfStock = outOfStockCount(products);

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
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.sm),
                    child: FulusActionTile(
                      icon: FulusIcons.arrowUp,
                      label: 'Record stock',
                      subtitle: 'Add stock or record a movement',
                      onTap: () => context.pushNamed('stockRecordMovement'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.sm),
                    child: FulusSearchField(
                      controller: searchController,
                      hintText: 'Search products, SKU, barcode…',
                      onChanged: (value) => ref.read(stockFilterProvider.notifier).state = filter.copyWith(query: value),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.md),
                    child: FulusStatGrid(
                      spacing: AppSpacing.sm,
                      minTileWidth: 150,
                      cards: [
                        FulusStatCard(
                          icon: FulusIcons.stock,
                          label: 'Stock available',
                          value: '${totalUnits.toStringAsFixed(totalUnits == totalUnits.roundToDouble() ? 0 : 1)} units',
                        ),
                        FulusStatCard(
                          icon: FulusIcons.money,
                          label: 'Stock value',
                          value: formatMoney(totalValue, symbol: currencySymbol, compact: true),
                        ),
                        FulusStatCard(
                          icon: FulusIcons.warning,
                          label: 'Low stock',
                          value: '$lowStockCount items',
                          valueColor: lowStockCount > 0 ? AppColors.warningOf(context) : null,
                          onTap: lowStockCount > 0
                              ? () => ref.read(stockFilterProvider.notifier).state =
                                  filter.copyWith(lowStockOnly: true, outOfStockOnly: false)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    child: FulusChipRow(children: [
                      for (final category in categories)
                        FulusChip(
                          label: category.name,
                          selected: filter.categoryId == category.localId,
                          onTap: () => ref.read(stockFilterProvider.notifier).state =
                              filter.copyWith(
                                categoryId: filter.categoryId == category.localId
                                    ? null
                                    : category.localId,
                              ),
                        ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: FulusChipRow(children: [
                            FulusChip(label: 'All', selected: !filter.lowStockOnly && !filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: false, outOfStockOnly: false)),
                            FulusChip(label: 'Low stock · $lowStockCount', selected: filter.lowStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: !filter.lowStockOnly, outOfStockOnly: false)),
                            FulusChip(label: 'Out of stock · $outOfStock', selected: filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(outOfStockOnly: !filter.outOfStockOnly, lowStockOnly: false)),
                          ]),
                        ),
                        FulusIconButton(icon: FulusIcons.sort, tooltip: 'Sort products', onPressed: () => _showSortSheet(context, ref, filter)),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inset, vertical: AppSpacing.xs),
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
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: width >= 1200 ? inset - AppSpacing.lg : 0),
                          child: ProductListTile(
                            item: item,
                            category: item.product.categoryId == null ? null : categoryById[item.product.categoryId],
                            onTap: () => context.pushNamed('stockProductDetail', pathParameters: {'productId': item.product.localId}),
                          ),
                        );
                      },
                      childCount: filtered.length * 2 - 1,
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxxl)),
              ],
            );
          },
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

