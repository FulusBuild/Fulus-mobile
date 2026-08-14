import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
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
    final cartState = context.watch<CartCubit>().state;
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
            child: switch (cartState) {
              CartFailure(:final message) => FulusErrorState(message: message),
              CartLoaded state => _ProductArea(
                  state: state,
                  query: _query,
                  categoryId: _selectedCategoryId,
                ),
              _ => const FulusLoadingIndicator(),
            },
          ),
          if (cartState is CartLoaded && cartState.items.isNotEmpty)
            _CartSummaryBar(state: cartState),
        ],
      ),
    );
  }
}

class _ProductArea extends StatelessWidget {
  const _ProductArea({required this.state, required this.query, required this.categoryId});

  final CartLoaded state;
  final String query;
  final String? categoryId;

  @override
  Widget build(BuildContext context) {
    // "Loading products" — the catalog stream hasn't emitted at all
    // yet, distinct from a catalog that has loaded and is genuinely
    // empty.
    if (!state.catalogLoaded) {
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
    if (state.catalog.isEmpty) {
      return FulusEmptyState(
        headline: 'No products yet',
        body: 'Add products from Stock once it\'s set up, or use Quick Sale for anything you\'re selling today.',
        icon: Icons.storefront_outlined,
        actionLabel: 'Quick Sale',
        onAction: () => QuickSaleSheet.show(context),
      );
    }

    final normalizedQuery = query.trim().toLowerCase();
    final products = state.catalog.values.where((p) {
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
          _ProductTile(productWithStock: products[i], currencySymbol: state.currencySymbol),
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
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAltOf(context),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: AppIconSize.emphasis,
                  color: AppColors.textSecondaryOf(context),
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
              '$currencySymbol${product.sellingPrice.toStringAsFixed(2)}',
              style: AppTypography.body.copyWith(color: AppColors.primaryOf(context)),
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              ),
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
                      '${state.currencySymbol}${state.total.toStringAsFixed(2)}',
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
