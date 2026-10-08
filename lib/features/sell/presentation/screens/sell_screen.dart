import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/formatting.dart';
import '../../../../domain/entities/category.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/screens/barcode_scan_screen.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../stock/application/stock_providers.dart';
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
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategoryId;
  CartCubit? _cartCubit;

  @override
  void dispose() {
    _searchController.dispose();
    _cartCubit?.close();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _retryCart() {
    final cubit = _cartCubit;
    _cartCubit = null;
    cubit?.close();
    if (mounted) setState(() {});
  }

  Future<void> _scanProduct() async {
    final barcode = await BarcodeScanScreen.scan(context, title: 'Scan product barcode');
    if (barcode == null || !mounted) return;
    final cubit = _cartCubit;
    if (cubit == null) return;
    final current = cubit.state;
    if (current is! CartLoaded) return;

    ProductWithStock? match;
    for (final entry in current.catalog.values) {
      if (entry.product.barcode?.trim() == barcode.trim()) {
        match = entry;
        break;
      }
    }

    if (match == null) {
      _searchController.text = barcode;
      setState(() => _query = barcode);
      showFulusSnackbar(context, message: 'No product found for that barcode.');
      return;
    }

    if (match.product.tracksStock && match.currentStock <= 0) {
      showFulusSnackbar(context, message: '${match.product.name} is out of stock.');
      return;
    }

    try {
      await cubit.addProduct(match.product.localId);
      FulusHaptics.selection();
      if (mounted) showFulusSnackbar(context, message: '${match.product.name} added to the cart.');
    } on StateError catch (e) {
      FulusHaptics.error();
      if (mounted) showFulusSnackbar(context, message: e.message);
    }
  }

  CartCubit _ensureCartCubit(String locationId) {
    final existing = _cartCubit;
    if (existing != null && existing.locationId != locationId) {
      // Drafts are persisted per location, so closing the old cubit does not
      // discard its unsaved cart. It only tears down its A-scoped streams.
      _cartCubit = null;
      unawaited(existing.close());
    }
    final current = _cartCubit;
    if (current != null) return current;
    final cubit = CartCubit(
      draftCartRepository: ref.read(draftCartRepositoryProvider),
      productRepository: ref.read(productRepositoryProvider),
      customerRepository: ref.read(customerRepositoryProvider),
      businessSettingsRepository: ref.read(businessSettingsRepositoryProvider),
      locationId: locationId,
      diagnosticLogger: ref.read(diagnosticLoggerProvider),
    );
    _cartCubit = cubit;
    return cubit;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: ref.watch(activeLocationIdProvider.future),
      builder: (context, locationSnapshot) {
        if (locationSnapshot.connectionState != ConnectionState.done) {
          return const FulusScreen(
            title: 'Sell',
            applyPadding: false,
            body: _SellLocationSkeleton(),
          );
        }
        if (locationSnapshot.hasError || !locationSnapshot.hasData || locationSnapshot.data!.isEmpty) {
          return FulusScreen(
            title: 'Sell',
            body: FulusErrorState(
              message: "Couldn't open Sell right now.",
              reassurance: 'Your products and sales are still safe on this device.',
              onRetry: () {
                ref.invalidate(activeLocationIdProvider);
                setState(() {});
              },
            ),
          );
        }

        final cubit = _ensureCartCubit(locationSnapshot.data!);
        return BlocProvider.value(
          value: cubit,
          child: _SellContent(
            searchController: _searchController,
            query: _query,
            selectedCategoryId: _selectedCategoryId,
            onQueryChanged: (value) => setState(() => _query = value),
            onCategoryChanged: (value) => setState(() => _selectedCategoryId = value),
            onClearSearch: _clearSearch,
            onScan: _scanProduct,
            onRetry: _retryCart,
          ),
        );
      },
    );
  }
}

class _SellContentSkeleton extends StatelessWidget {
  const _SellContentSkeleton();

  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
          child: Row(
            children: [
              const Expanded(child: FulusSkeletonBox(height: 48)),
              const SizedBox(width: AppSpacing.sm),
              const FulusSkeletonBox(width: 92, height: 48),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: FulusSkeletonBox(height: 46),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpacing.md),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (_, __) => const FulusSkeletonBox(),
            ),
          ),
        ),
      ],
    );
  }
}

class _SellLocationSkeleton extends StatelessWidget {
  const _SellLocationSkeleton();

  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
          child: const FulusDelayedSkeleton(
            skeleton: FulusSkeletonBox(height: 52),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: inset),
            scrollDirection: Axis.horizontal,
            children: const [
              FulusSkeletonBox(width: 64, height: 36),
              SizedBox(width: AppSpacing.sm),
              FulusSkeletonBox(width: 92, height: 36),
              SizedBox(width: AppSpacing.sm),
              FulusSkeletonBox(width: 82, height: 36),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xl),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width < 390 ? 2 : 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.82,
            ),
            itemCount: 6,
            itemBuilder: (_, __) => const FulusCardSkeleton(),
          ),
        ),
      ],
    );
  }
}

class _SellContent extends ConsumerWidget {
  const _SellContent({
    required this.searchController,
    required this.query,
    required this.selectedCategoryId,
    required this.onQueryChanged,
    required this.onCategoryChanged,
    required this.onClearSearch,
    required this.onScan,
    required this.onRetry,
  });

  final TextEditingController searchController;
  final String query;
  final String? selectedCategoryId;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onScan;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).asData?.value ?? const <Category>[];
    final categoryById = {for (final category in categories) category.localId: category};

    return FulusScreen(
      title: 'Sell',
      applyPadding: false,
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state is CartFailure) {
            return FulusErrorState(message: state.message, onRetry: onRetry);
          }

          final catalog = switch (state) {
            CartHydrating s => s.catalog,
            CartLoaded s => s.catalog,
            _ => const <String, ProductWithStock>{},
          };
          final catalogLoaded = switch (state) {
            CartHydrating s => s.catalogLoaded,
            CartLoaded s => s.catalogLoaded,
            _ => false,
          };
          final currency = switch (state) {
            CartHydrating s => s.currencySymbol,
            CartLoaded s => s.currencySymbol,
            _ => '₦',
          };
          final cartReady = state is CartLoaded;

          if (state is CartInitial) return const _SellContentSkeleton();

          final inset = fulusHorizontalInset(context);
          final categoryIds = catalog.values
              .map((entry) => entry.product.categoryId)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort((a, b) =>
                (categoryById[a]?.name ?? a).compareTo(categoryById[b]?.name ?? b));

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    inset, AppSpacing.md, inset, AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.15;
                    final scanButton = FulusButton(
                      variant: FulusButtonVariant.primary,
                      icon: FulusIcons.scan,
                      label: 'Scan',
                      onPressed: cartReady ? onScan : null,
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FulusSearchField(
                            controller: searchController,
                            hintText: 'Search by product name or barcode',
                            onChanged: onQueryChanged,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          scanButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FulusSearchField(
                            controller: searchController,
                            hintText: 'Search by product name or barcode',
                            onChanged: onQueryChanged,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        scanButton,
                      ],
                    );
                  },
                ),
              ),
              if (query.trim().isEmpty && cartReady)
                Padding(
                  padding: EdgeInsets.fromLTRB(inset, AppSpacing.xs, inset, AppSpacing.sm),
                  child: _QuickSaleBar(onTap: () => QuickSaleSheet.show(context)),
                ),
              if (categoryIds.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: inset),
                    scrollDirection: Axis.horizontal,
                    children: [
                      FulusChip(
                        label: 'All',
                        selected: selectedCategoryId == null,
                        onTap: () => onCategoryChanged(null),
                      ),
                      for (final id in categoryIds)
                        FulusChip(
                          label: categoryById[id]?.name ?? id,
                          selected: selectedCategoryId == id,
                          onTap: () => onCategoryChanged(id),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _ProductList(
                  catalog: catalog,
                  catalogLoaded: catalogLoaded,
                  currency: currency,
                  query: query,
                  categoryId: selectedCategoryId,
                  onClearSearch: onClearSearch,
                  cartReady: cartReady,
                ),
              ),
              if (state is CartLoaded && (state).items.isNotEmpty)
                _CartSummaryBar(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.catalog,
    required this.catalogLoaded,
    required this.currency,
    required this.query,
    required this.categoryId,
    required this.onClearSearch,
    required this.cartReady,
  });

  final Map<String, ProductWithStock> catalog;
  final bool catalogLoaded;
  final String currency;
  final String query;
  final String? categoryId;
  final VoidCallback onClearSearch;
  final bool cartReady;

  @override
  Widget build(BuildContext context) {
    if (!catalogLoaded) return const _SellContentSkeleton();

    final q = query.trim().toLowerCase();
    final products = catalog.values.where((entry) {
      final p = entry.product;
      if (categoryId != null && p.categoryId != categoryId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList()..sort((a, b) => a.product.name.compareTo(b.product.name));

    if (products.isEmpty) {
      return FulusEmptyState(
        headline: 'No products found',
        body: q.isEmpty ? 'Add products from Stock to start selling.' : 'Nothing matches “$query”.',
        icon: FulusIcons.search,
        actionLabel: q.isEmpty && cartReady ? 'Quick Sale' : 'Clear search',
        onAction: q.isEmpty && cartReady ? () => QuickSaleSheet.show(context) : onClearSearch,
      );
    }

    final inset = fulusHorizontalInset(context);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xl),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.sizeOf(context).width < 390 ? 2 : 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.82,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductRow(
          entry: product,
          currency: currency,
          enabled: cartReady,
        );
      },
    );
  }
}

class _QuickSaleBar extends StatelessWidget {
  const _QuickSaleBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: const SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(FulusIcons.quickActions, color: Colors.white, size: 24),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'Quick Sale',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                Spacer(),
                Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.entry, required this.currency, required this.enabled});
  final ProductWithStock entry;
  final String currency;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    final out = product.tracksStock && entry.currentStock <= 0;
    final initial = product.name.trim().isEmpty ? '?' : product.name.trim()[0].toUpperCase();

    return FulusPressable(
      onPressed: !enabled || out ? null : () => _add(context),
      semanticsLabel: product.name,
      child: Opacity(
        opacity: out ? 0.5 : 1,
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
                  ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  width: double.infinity,
                  color: AppColors.selectedTintOf(context),
                  alignment: Alignment.center,
                  child: product.photoPath == null
                      ? Text(
                          initial,
                          style: AppTypography.heading.copyWith(
                            color: AppColors.primaryOf(context),
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : (product.photoPath!.startsWith('http://') || product.photoPath!.startsWith('https://'))
                          ? Image.network(
                              product.photoPath!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Text(
                                initial,
                                style: AppTypography.heading.copyWith(
                                  color: AppColors.primaryOf(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : Image.file(
                                  File(product.photoPath!),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => Text(
                                    initial,
                                    style: AppTypography.heading.copyWith(
                                      color: AppColors.primaryOf(context),
                                    ),
                                  ),
                                ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatMoney(product.sellingPrice, symbol: currency),
              style: AppTypography.body.copyWith(
                color: AppColors.primaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            ],
          ),
        ),
          if (out)
            Positioned(
              top: 8,
              right: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.errorOf(context), shape: BoxShape.circle),
                child: SizedBox(width: 8, height: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final product = entry.product;
    try {
      await context.read<CartCubit>().addProductQuantity(
            product.localId,
            1,
          );
      FulusHaptics.selection();
      if (context.mounted) {
        showFulusSnackbar(
          context,
          message: '1 × ${product.name} added to the cart.',
        );
      }
    } on StateError catch (e) {
      FulusHaptics.error();
      if (context.mounted) showFulusSnackbar(context, message: e.message);
    }
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.state});
  final CartLoaded state;
  @override
  Widget build(BuildContext context) {
    final inset = fulusHorizontalInset(context);
    return SafeArea(top: false, child: Padding(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.sm),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            final cubit = context.read<CartCubit>();
            Navigator.of(context).push(
              PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, __, ___) =>
                    BlocProvider.value(value: cubit, child: const CartScreen()),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(height: 54, child: Row(children: [
            const SizedBox(width: AppSpacing.md),
            FulusIconVisual(icon: FulusIcons.shoppingCart, color: AppColors.onColor(AppColors.primary), size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(state.itemCount.toString() + ' items', style: AppTypography.body.copyWith(color: AppColors.onColor(AppColors.primary), fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(formatMoney(state.total, symbol: state.currencySymbol), style: AppTypography.heading.copyWith(color: AppColors.onColor(AppColors.primary), fontWeight: FontWeight.w800)),
            const SizedBox(width: AppSpacing.sm),
            Text('Charge', style: AppTypography.body.copyWith(color: AppColors.onColor(AppColors.primary), fontWeight: FontWeight.w700)),
            const SizedBox(width: AppSpacing.md),
          ])),
        ),
      ),
    ));
  }
}
