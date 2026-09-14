import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../core/ux/consumer_polish.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/screens/barcode_scan_screen.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import '../widgets/quick_sale_sheet.dart';
import 'cart_screen.dart';

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  late Future<String> _locationIdFuture = _resolveLocationId();

  Future<String> _resolveLocationId() => ref.read(resolveActiveLocationProvider).call();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _locationIdFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FulusScreen(
            title: 'Sell',
            body: FulusErrorState(
              message: "Couldn't open Sell.",
              reassurance: 'Nothing was sold or lost — this is only about loading the screen.',
              onRetry: () => setState(() => _locationIdFuture = _resolveLocationId()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const FulusScreen(title: 'Sell', body: FulusLoadingIndicator());
        }
        return BlocProvider(
          create: (_) => CartCubit(
            draftCartRepository: ref.read(draftCartRepositoryProvider),
            productRepository: ref.read(productRepositoryProvider),
            customerRepository: ref.read(customerRepositoryProvider),
            businessSettingsRepository: ref.read(businessSettingsRepositoryProvider),
            locationId: snapshot.data!,
            diagnosticLogger: ref.read(diagnosticLoggerProvider),
          ),
          child: const _SellScreenBody(),
        );
      },
    );
  }
}

class _SellScreenBody extends ConsumerStatefulWidget {
  const _SellScreenBody();

  @override
  ConsumerState<_SellScreenBody> createState() => _SellScreenBodyState();
}

class _SellScreenBodyState extends ConsumerState<_SellScreenBody> {
  final _searchController = TextEditingController();
  late final Stream<List<Category>> _categoriesStream = ref.read(categoryRepositoryProvider).watchCategories();
  String _query = '';
  String? _selectedCategoryId;
  final Set<String> _favoriteIds = <String>{};
  bool _favoritesOnly = false;
  bool _favoritesLoaded = false;
  static const _favoritesKey = 'fulus_sell_favorite_product_ids';

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(_favoritesKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _favoriteIds
        ..clear()
        ..addAll(saved);
      _favoritesLoaded = true;
    });
  }

  Future<void> _toggleFavorite(String productId) async {
    setState(() {
      if (!_favoriteIds.add(productId)) _favoriteIds.remove(productId);
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, _favoriteIds.toList());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedCategoryId = null;
    });
  }

  Future<void> _scanAndAdd(BuildContext context) async {
    final barcode = await BarcodeScanScreen.scan(context, title: 'Scan a product');
    if (barcode == null || !context.mounted) return;
    final cartState = context.read<CartCubit>().state;
    if (cartState is! CartLoaded) return;

    ProductWithStock? match;
    for (final entry in cartState.catalog.values) {
      if (entry.product.barcode == barcode) {
        match = entry;
        break;
      }
    }

    if (match == null) {
      showFulusSnackbar(
        context,
        message: 'No product found with that barcode.',
        actionLabel: 'Quick Sale',
        onAction: () => QuickSaleSheet.show(context),
      );
      return;
    }

    try {
      await context.read<CartCubit>().addProduct(match.product.localId);
      if (context.mounted) {
        FulusHaptics.selection();
        showFulusSnackbar(context, message: '${match.product.name} added');
      }
    } on StateError catch (e) {
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  Future<void> _addProduct(BuildContext context, ProductWithStock product) async {
    try {
      await context.read<CartCubit>().addProduct(product.product.localId);
      if (context.mounted) FulusHaptics.selection();
    } on StateError catch (e) {
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sell',
      applyPadding: false,
      actions: [
        FulusIconButton(
          icon: Icons.qr_code_scanner_outlined,
          tooltip: 'Scan a barcode',
          onPressed: () => _scanAndAdd(context),
        ),
        FulusIconButton(
          icon: Icons.assignment_return_outlined,
          tooltip: 'Refund a sale',
          onPressed: () => context.pushNamed('sellRefundSearch'),
        ),
        FulusIconButton(
          icon: Icons.storefront_outlined,
          tooltip: 'Quick Sale',
          onPressed: () => QuickSaleSheet.show(context),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: FulusSearchField(
              controller: _searchController,
              hintText: 'Search products…',
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: FulusChipRow(
              children: [
                FulusChip(
                  label: 'All',
                  selected: !_favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = false),
                ),
                FulusChip(
                  label: 'Favorites',
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = true),
                ),
              ],
            ),
          ),
          StreamBuilder<List<Category>>(
            stream: _categoriesStream,
            builder: (context, snapshot) {
              final categories = snapshot.data ?? const <Category>[];
              if (categories.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: FulusChipRow(
                  children: [
                    FulusChip(
                      label: 'All categories',
                      selected: _selectedCategoryId == null,
                      onTap: () => setState(() => _selectedCategoryId = null),
                    ),
                    for (final category in categories)
                      FulusChip(
                        label: category.name,
                        selected: _selectedCategoryId == category.localId,
                        onTap: () => setState(() => _selectedCategoryId = category.localId),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: BlocSelector<CartCubit, CartState, _ProductAreaState>(
              selector: (state) => switch (state) {
                CartFailure(:final message) => (errorMessage: message, catalogSlice: null),
                CartLoaded state => (
                    errorMessage: null,
                    catalogSlice: (
                      catalog: state.catalog,
                      catalogLoaded: state.catalogLoaded,
                      currencySymbol: state.currencySymbol,
                    ),
                  ),
                _ => (errorMessage: null, catalogSlice: null),
              },
              builder: (context, result) {
                if (result.errorMessage != null) return FulusErrorState(message: result.errorMessage!);
                final slice = result.catalogSlice;
                if (slice == null) return const FulusLoadingIndicator();
                return _ProductArea(
                  catalog: slice.catalog,
                  catalogLoaded: slice.catalogLoaded,
                  currencySymbol: slice.currencySymbol,
                  query: _query,
                  categoryId: _selectedCategoryId,
                  favoritesOnly: _favoritesOnly,
                  favoriteIds: _favoriteIds,
                  favoritesLoaded: _favoritesLoaded,
                  onClearSearch: _clearSearch,
                  onAddProduct: (product) => _addProduct(context, product),
                  onToggleFavorite: _toggleFavorite,
                );
              },
            ),
          ),
          BlocBuilder<CartCubit, CartState>(
            builder: (context, cartState) {
              if (cartState is CartLoaded && cartState.items.isNotEmpty) {
                return _CartSummaryBar(state: cartState);
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

typedef _CatalogSlice = ({Map<String, ProductWithStock> catalog, bool catalogLoaded, String currencySymbol});
typedef _ProductAreaState = ({String? errorMessage, _CatalogSlice? catalogSlice});

class _ProductArea extends StatelessWidget {
  const _ProductArea({
    required this.catalog,
    required this.catalogLoaded,
    required this.currencySymbol,
    required this.query,
    required this.categoryId,
    required this.favoritesOnly,
    required this.favoriteIds,
    required this.favoritesLoaded,
    required this.onClearSearch,
    required this.onAddProduct,
    required this.onToggleFavorite,
  });

  final Map<String, ProductWithStock> catalog;
  final bool catalogLoaded;
  final String currencySymbol;
  final String query;
  final String? categoryId;
  final bool favoritesOnly;
  final Set<String> favoriteIds;
  final bool favoritesLoaded;
  final VoidCallback onClearSearch;
  final Future<void> Function(ProductWithStock product) onAddProduct;
  final Future<void> Function(String productId) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    if (!catalogLoaded || !favoritesLoaded) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.82,
        ),
        itemCount: 6,
        itemBuilder: (context, i) => const FulusDelayedSkeleton(skeleton: FulusCardSkeleton()),
      );
    }

    if (catalog.isEmpty) {
      return FulusEmptyState(
        headline: 'No products yet',
        body: "Add products from Stock once it's set up, or use Quick Sale for anything you're selling today.",
        icon: Icons.storefront_outlined,
        actionLabel: 'Quick Sale',
        onAction: () => QuickSaleSheet.show(context),
      );
    }

    final normalizedQuery = query.trim().toLowerCase();
    final products = catalog.values.where((p) {
      final product = p.product;
      if (favoritesOnly && !favoriteIds.contains(product.localId)) return false;
      if (categoryId != null && product.categoryId != categoryId) return false;
      if (normalizedQuery.isEmpty) return true;
      return product.name.toLowerCase().contains(normalizedQuery) ||
          product.sku.toLowerCase().contains(normalizedQuery) ||
          (product.barcode?.toLowerCase().contains(normalizedQuery) ?? false);
    }).toList()
      ..sort((a, b) {
        final favoriteOrder = (favoriteIds.contains(b.product.localId) ? 1 : 0) -
            (favoriteIds.contains(a.product.localId) ? 1 : 0);
        return favoriteOrder != 0 ? favoriteOrder : a.product.name.compareTo(b.product.name);
      });

    if (products.isEmpty) {
      return FulusEmptyState(
        headline: favoritesOnly ? 'No favorites yet' : 'No matches',
        body: favoritesOnly
            ? 'Star your fastest-selling products to keep them one tap away.'
            : normalizedQuery.isEmpty
                ? 'No products in this category yet.'
                : 'Nothing matches "$query" — try a different search, or use Quick Sale.',
        icon: favoritesOnly ? Icons.star_border : Icons.search_off,
        actionLabel: favoritesOnly ? 'Show all products' : 'Clear search',
        onAction: favoritesOnly ? () {} : onClearSearch,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxxl),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.82,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) => _ProductTile(
        productWithStock: products[i],
        currencySymbol: currencySymbol,
        isFavorite: favoriteIds.contains(products[i].product.localId),
        onAdd: onAddProduct,
        onToggleFavorite: onToggleFavorite,
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.productWithStock,
    required this.currencySymbol,
    required this.isFavorite,
    required this.onAdd,
    required this.onToggleFavorite,
  });

  final ProductWithStock productWithStock;
  final String currencySymbol;
  final bool isFavorite;
  final Future<void> Function(ProductWithStock product) onAdd;
  final Future<void> Function(String productId) onToggleFavorite;

  bool get _outOfStock => productWithStock.product.tracksStock && productWithStock.currentStock <= 0;

  @override
  Widget build(BuildContext context) {
    final product = productWithStock.product;
    return Opacity(
      opacity: _outOfStock ? AppOpacity.disabled : 1.0,
      child: Stack(
        children: [
          Positioned.fill(
            child: FulusPressable(
              semanticsLabel: _outOfStock ? '${product.name}, out of stock' : 'Add ${product.name} to sale',
              onPressed: _outOfStock ? null : () => onAdd(productWithStock),
              child: FulusCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.selectedTintOf(context),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          alignment: Alignment.center,
                          child: product.photoPath == null
                              ? Icon(Icons.inventory_2_outlined, size: AppIconSize.emphasis, color: AppColors.primaryOf(context).withValues(alpha: 0.55))
                              : Image.file(
                                  File(product.photoPath!),
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  errorBuilder: (context, error, stackTrace) => Icon(Icons.inventory_2_outlined, size: AppIconSize.emphasis, color: AppColors.primaryOf(context).withValues(alpha: 0.55)),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(formatMoney(product.sellingPrice, symbol: currencySymbol), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                    if (_outOfStock)
                      Text('Out of stock', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.errorOf(context)))
                    else if (product.tracksStock && productWithStock.isLowStock)
                      Text('Only ${productWithStock.currentStock} left', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.warningOf(context))),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Material(
              color: AppColors.surfaceOf(context).withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: FulusIconButton(
                icon: isFavorite ? Icons.star : Icons.star_border,
                tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () => onToggleFavorite(product.localId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.state});

  final CartLoaded state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.surfaceOf(context), boxShadow: AppElevation.liftOf(context)),
        child: SizedBox(
          height: AppTouchTarget.minimum,
          child: Material(
            color: AppColors.primaryOf(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: FulusPressable(
              semanticsLabel: 'View cart, ${state.itemCount} ${state.itemCount == 1 ? 'item' : 'items'}',
              onPressed: () {
                final cubit = context.read<CartCubit>();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlocProvider.value(value: cubit, child: const CartScreen())));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    FulusBadge(count: state.itemCount),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        state.itemCount == 1 ? 'View Cart · 1 item' : 'View Cart · ${state.itemCount} items',
                        style: AppTypography.buttonLabel.copyWith(color: AppColors.onPrimaryOf(context)),
                      ),
                    ),
                    Text(formatMoney(state.total, symbol: state.currencySymbol), style: AppTypography.mono.copyWith(color: AppColors.onPrimaryOf(context), fontWeight: FontWeight.w700)),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(Icons.arrow_forward, color: AppColors.onPrimaryOf(context), size: AppIconSize.compact),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
