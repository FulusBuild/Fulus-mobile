import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/screens/barcode_scan_screen.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import '../widgets/quick_sale_sheet.dart';
import 'cart_screen.dart';

/// The `/sell` route's real screen — router.dart's previous placeholder
/// ("Volume 5 — cart, checkout. Not yet built.") replaced here. Task:
/// find/select a product, add to cart, adjust quantity, review cart,
/// optionally pick a customer, pay, complete the sale.
///
/// Resolves [locationId] once via the shared `ResolveActiveLocation`
/// mechanism (`activeLocationIdProvider` — every feature that needs
/// "the active location" goes through this same resolver now, rather
/// than each maintaining its own fallback), then hands it to a single
/// [CartCubit] kept alive for the lifetime of this branch's own
/// navigation stack (`StatefulShellRoute.indexedStack` keeps Sell's
/// stack independent of Home/Stock/Money/More — Decision 14's "never
/// silently lost" applies even just switching tabs, not only an app
/// restart).
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  late Future<String> _locationIdFuture = _resolveLocationId();

  // CORRECTED: this used to read `watchLocations().first` directly and
  // throw if the business had zero locations — true of every mobile-
  // only business before ResolveActiveLocation existed, since nothing
  // ever created one. Now delegates to the same resolver every other
  // feature uses, which get-or-creates a location rather than leaving
  // this screen permanently unusable for a mobile-only business.
  Future<String> _resolveLocationId() {
    return ref.read(resolveActiveLocationProvider).call();
  }

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
              onRetry: () => setState(() {
                _locationIdFuture = _resolveLocationId();
              }),
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
  late final Stream<List<Category>> _categoriesStream =
      ref.read(categoryRepositoryProvider).watchCategories();
  String _query = '';
  String? _selectedCategoryId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      showFulusSnackbar(context, message: "No product found with that barcode.");
      return;
    }
    try {
      await context.read<CartCubit>().addProduct(match.product.localId);
      if (context.mounted) showFulusSnackbar(context, message: '${match.product.name} added.');
    } on StateError catch (e) {
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sell',
      applyPadding: false,
      actions: [
        // Gap fix: BarcodeScannerService existed with no caller anywhere
        // — see BarcodeScanScreen's own header comment.
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
              onChanged: (value) => setState(() => _query = value),
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
                      label: 'All',
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
            // Perf: BlocSelector, not a plain context.watch — this
            // subtree (and every visible _ProductTile inside
            // _ProductArea) now only rebuilds when the catalog, its
            // loaded flag, or the currency symbol actually change.
            // Cart-only changes (add/remove/qty/payments/draft) used
            // to rebuild this whole area, including every visible
            // product tile, on every single cart tap; now they don't
            // touch this widget at all. Relies on CartCubit keeping
            // `catalog` reference-stable across those emissions (see
            // its _catalogSnapshot field) — without that, this
            // selector would see a "new" catalog Map on every emission
            // and rebuild just as often as before.
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
                final errorMessage = result.errorMessage;
                if (errorMessage != null) {
                  return FulusErrorState(message: errorMessage);
                }
                final slice = result.catalogSlice;
                if (slice == null) {
                  return const FulusLoadingIndicator();
                }
                return _ProductArea(
                  catalog: slice.catalog,
                  catalogLoaded: slice.catalogLoaded,
                  currencySymbol: slice.currencySymbol,
                  query: _query,
                  categoryId: _selectedCategoryId,
                );
              },
            ),
          ),
          // Left as a plain BlocBuilder (full-state watch), not a
          // selector — almost every CartLoaded field (items, total,
          // itemCount) is genuinely relevant to what this bar shows,
          // so there's nothing meaningful to narrow. Scoping the watch
          // to just this widget (instead of the old top-of-build
          // watch) still means a cart change only rebuilds this small
          // bar now, not the search field and category row above it.
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

// Perf: the two small record typedefs the BlocSelector above uses to
// pick out just the fields _ProductArea needs. Records get structural
// equality for free (field-by-field ==), which is what lets
// BlocSelector detect "nothing relevant changed" — for `catalog`
// specifically that's an identity comparison (Maps compare by
// reference), which is why CartCubit keeping catalog
// reference-stable across cart-only emissions (see its
// _catalogSnapshot field) is what makes the selector actually skip
// work rather than always seeing "different."
typedef _CatalogSlice = ({
  Map<String, ProductWithStock> catalog,
  bool catalogLoaded,
  String currencySymbol,
});

typedef _ProductAreaState = ({String? errorMessage, _CatalogSlice? catalogSlice});

class _ProductArea extends StatelessWidget {
  const _ProductArea({
    required this.catalog,
    required this.catalogLoaded,
    required this.currencySymbol,
    required this.query,
    required this.categoryId,
  });

  // Perf: takes just the catalog-derived fields it actually reads,
  // rather than the whole CartLoaded state, so the BlocSelector in
  // _SellScreenBodyState.build() can skip rebuilding this widget (and
  // every visible _ProductTile beneath it) when only cart items,
  // payments, or the draft change — none of which this widget uses.
  final Map<String, ProductWithStock> catalog;
  final bool catalogLoaded;
  final String currencySymbol;
  final String query;
  final String? categoryId;

  @override
  Widget build(BuildContext context) {
    // "Loading products" — the catalog stream hasn't emitted at all
    // yet, distinct from a catalog that has loaded and is genuinely
    // empty.
    if (!catalogLoaded) {
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

    // "Empty product catalogue" — no products at all in this business
    // yet. Stock/Inventory (Volume 6) isn't built as a screen yet
    // either, so Quick Sale is the one real way to make a sale right
    // now — the empty state's action reflects that honestly rather
    // than pointing at a screen that doesn't exist.
    if (catalog.isEmpty) {
      return FulusEmptyState(
        headline: 'No products yet',
        body: 'Add products from Stock once it\'s set up, or use Quick Sale for anything you\'re selling today.',
        icon: Icons.storefront_outlined,
        actionLabel: 'Quick Sale',
        onAction: () => QuickSaleSheet.show(context),
      );
    }

    final normalizedQuery = query.trim().toLowerCase();
    final products = catalog.values.where((p) {
      final product = p.product;
      if (categoryId != null && product.categoryId != categoryId) return false;
      if (normalizedQuery.isEmpty) return true;
      return product.name.toLowerCase().contains(normalizedQuery) ||
          product.sku.toLowerCase().contains(normalizedQuery) ||
          (product.barcode?.toLowerCase().contains(normalizedQuery) ?? false);
    }).toList()
      ..sort((a, b) => a.product.name.compareTo(b.product.name));

    // "Search with no results"
    if (products.isEmpty) {
      return FulusEmptyState(
        headline: 'No matches',
        body: normalizedQuery.isEmpty
            ? 'No products in this category yet.'
            : 'Nothing matches "$query" — try a different search, or use Quick Sale.',
        icon: Icons.search_off,
        actionLabel: 'Quick Sale',
        onAction: () => QuickSaleSheet.show(context),
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
      itemBuilder: (context, i) =>
          _ProductTile(productWithStock: products[i], currencySymbol: currencySymbol),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.productWithStock, required this.currencySymbol});

  final ProductWithStock productWithStock;
  final String currencySymbol;

  bool get _outOfStock =>
      productWithStock.product.tracksStock && productWithStock.currentStock <= 0;

  @override
  Widget build(BuildContext context) {
    final product = productWithStock.product;
    return Opacity(
      opacity: _outOfStock ? AppOpacity.disabled : 1.0,
      child: FulusCard(
        onTap: () => _handleTap(context),
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
                  // Product Design Bible Volume 6 already lets Add
                  // Product capture a photo (AddEditProductScreen,
                  // `photoPath`) — this tile just wasn't reading it,
                  // showing the same generic box icon for every product
                  // regardless. errorBuilder falls back to that same
                  // icon rather than a broken-image glyph if the file's
                  // gone missing from disk for some reason.
                  child: product.photoPath == null
                      ? Icon(
                          Icons.inventory_2_outlined,
                          size: AppIconSize.emphasis,
                          color: AppColors.primaryOf(context).withValues(alpha: 0.55),
                        )
                      : Image.file(
                          File(product.photoPath!),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          // Perf: photos come straight from the device
                          // camera (often several MB, thousands of
                          // pixels wide) but this tile only ever shows
                          // one at grid-thumbnail size. Without this,
                          // every tile decodes the full-resolution
                          // source into memory just to downscale it —
                          // expensive on both CPU (decode time, felt
                          // as jank while scrolling) and RAM (an
                          // ImageCache full of full-size bitmaps on a
                          // catalog this app is designed to scale to
                          // thousands of products — see
                          // product_list_tile.dart's own comment on
                          // that scale target). cacheWidth alone (not
                          // cacheHeight too) so the decoder preserves
                          // the source's own aspect ratio rather than
                          // stretching it — BoxFit.cover above still
                          // does the final crop-to-fit exactly as
                          // before, just against a far smaller bitmap.
                          // 300 is a generous upper bound for this
                          // tile's on-screen width on the phones this
                          // needs to feel fast on, not a tight fit.
                          cacheWidth: 300,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.inventory_2_outlined,
                            size: AppIconSize.emphasis,
                            color: AppColors.primaryOf(context).withValues(alpha: 0.55),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatMoney(product.sellingPrice, symbol: currencySymbol),
              style: AppTypography.body.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w600),
            ),
            if (_outOfStock)
              Text('Out of stock', style: AppTypography.caption.copyWith(color: AppColors.errorOf(context)))
            else if (product.tracksStock && productWithStock.isLowStock)
              Text(
                'Only ${productWithStock.currentStock} left',
                style: AppTypography.caption.copyWith(color: AppColors.warningOf(context)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    // "Product unavailable" — a plain, immediate explanation rather
    // than a silent no-op tap.
    if (_outOfStock) {
      showFulusSnackbar(context, message: '${productWithStock.product.name} is out of stock.');
      return;
    }
    try {
      // Awaited so the StateError addProduct throws for a race-lost
      // stock check actually reaches this catch — a fire-and-forget
      // call here would let that error surface as an unhandled Future
      // rejection instead.
      await context.read<CartCubit>().addProduct(productWithStock.product.localId);
    } on StateError catch (e) {
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
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
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          boxShadow: AppElevation.liftOf(context),
        ),
        child: SizedBox(
          height: AppTouchTarget.minimum,
          child: Material(
            color: AppColors.primaryOf(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                final cubit = context.read<CartCubit>();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(value: cubit, child: const CartScreen()),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    FulusBadge(count: state.itemCount),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'View Cart',
                        style: AppTypography.buttonLabel.copyWith(color: AppColors.onPrimaryOf(context)),
                      ),
                    ),
                    Text(
                      formatMoney(state.total, symbol: state.currencySymbol),
                      style: AppTypography.buttonLabel.copyWith(color: AppColors.onPrimaryOf(context)),
                    ),
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
