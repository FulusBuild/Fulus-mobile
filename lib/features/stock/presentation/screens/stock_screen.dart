import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../domain/entities/auth_user.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/permission.dart';
import '../../../../domain/entities/stock_movement.dart';
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
    final user = ref.watch(sessionProvider);
    final permissions = ref.watch(sessionPermissionsProvider).value ?? const <Permission>{};
    final canManageStock =
        user?.role == AuthRole.owner ||
        permissions.contains(Permission.manageStock);

    return FulusScreen(
      title: 'Stock',
      subtitle: 'See what you have and record stock changes',
      backgroundColor: AppColors.backgroundOf(context),
      
      applyPadding: false,
      actions: [
        if (canManageStock)
          FulusIconButton(
            icon: FulusIcons.add,
            tooltip: 'Add product',
            onPressed: () => context.pushNamed('stockAddProduct'),
          ),
        if (canManageStock)
          FulusIconButton(
            icon: FulusIcons.more,
            tooltip: 'More stock options',
            onPressed: () => _showStockActions(context),
          ),
      ],
      floatingActionButton: null,
      body: locationAsync.when(
        loading: () => const _StockLocationSkeleton(),
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
    final movementsAsync = ref.watch(stockMovementsProvider(locationId));
    final filter = ref.watch(stockFilterProvider);

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
              slivers: [                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.sm),
                    child: FulusSearchField(
                      controller: searchController,
                      hintText: 'Search products, SKU, barcode…',
                      onChanged: (value) => ref.read(stockFilterProvider.notifier).state = filter.copyWith(query: value),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, AppSpacing.sm),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 1.15,
                      children: [
                        _StockSummaryTile(
                          color: const Color(0xFF1473E6),
                          icon: FulusIcons.stock,
                          label: 'Products',
                          value: '${products.length}',
                          subtitle: 'Total items',
                        ),
                        _StockSummaryTile(
                          color: const Color(0xFF0BBE6E),
                          icon: FulusIcons.category,
                          label: 'Categories',
                          value: '${categories.length}',
                          subtitle: 'Categories',
                          onTap: () => context.pushNamed('stockCategories'),
                        ),
                        _StockSummaryTile(
                          color: const Color(0xFFFF8C00),
                          icon: FulusIcons.stockIn,
                          label: 'Stock In',
                          value: movementsAsync.asData?.value.where((m) => m.movementType == StockMovementType.stockIn).length.toString() ?? '—',
                          subtitle: 'Recent',
                          onTap: () => context.pushNamed('stockRecordMovement'),
                        ),
                        _StockSummaryTile(
                          color: const Color(0xFF7B3FF2),
                          icon: FulusIcons.stockMovement,
                          label: 'Stock Movement',
                          value: movementsAsync.asData?.value.length.toString() ?? '—',
                          subtitle: 'Recent activity',
                          onTap: () => context.pushNamed('stockHistory'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpacing.sm),
                      child: Material(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: true, outOfStockOnly: false),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Builder(builder: (context) {
                              const alertColor = Color(0xFFFF3B30);
                              final foreground = AppColors.onColor(alertColor);
                              final muted = foreground.withValues(alpha: 0.9);
                              return Row(children: [
                          Icon(FulusIcons.warning, color: foreground, size: 28),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
  lowStockCount == 1 ? '1 item low in stock' : '$lowStockCount items low in stock',
  style: TextStyle(color: foreground, fontSize: 14, fontWeight: FontWeight.w800),
),
                            Text('View details →', style: TextStyle(color: muted, fontSize: 14)),
                          ])),
                              Icon(FulusIcons.chevronRight, color: foreground),
                            ]);
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: FulusChipRow(children: [
                            FulusChip(compact: true, label: 'All', selected: !filter.lowStockOnly && !filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: false, outOfStockOnly: false)),
                            FulusChip(compact: true, label: 'Low stock · $lowStockCount', selected: filter.lowStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(lowStockOnly: !filter.lowStockOnly, outOfStockOnly: false)),
                            FulusChip(compact: true, label: 'Out of stock · $outOfStock', selected: filter.outOfStockOnly, onTap: () => ref.read(stockFilterProvider.notifier).state = filter.copyWith(outOfStockOnly: !filter.outOfStockOnly, lowStockOnly: false)),
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
                    child: Text('${filtered.length} products', style: AppTypography.caption.copyWith(color: Colors.white70)),
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

class _StockSummaryTile extends StatelessWidget {
  const _StockSummaryTile({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.onColor(color);
    final muted = foreground.withValues(alpha: 0.9);
    final child = SizedBox(
      height: 146,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FulusMetricCardColumn(
          icon: icon,
          iconColor: foreground,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(color: foreground, fontSize: 30, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '$label, $value',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: onTap == null
            ? child
            : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.md), child: child),
      ),
    );
  }
}


class _StockLocationSkeleton extends StatelessWidget {
  const _StockLocationSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset = width >= 1200
            ? ((width - 1120.0) / 2) + AppSpacing.lg
            : AppSpacing.lg;
        return ListView(
          padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xxxl),
          children: [
            const FulusDelayedSkeleton(
              skeleton: FulusSkeletonBox(height: 52),
            ),
            const SizedBox(height: AppSpacing.lg),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.15,
              children: const [
                FulusSkeletonBox(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
                FulusSkeletonBox(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
                FulusSkeletonBox(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
                FulusSkeletonBox(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const FulusListRowSkeleton(),
            const FulusListRowSkeleton(),
            const FulusListRowSkeleton(),
          ],
        );
      },
    );
  }
}
