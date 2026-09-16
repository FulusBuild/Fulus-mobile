import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/ux/consumer_polish.dart';
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
    if (existing != null) return existing;
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
            subtitle: 'Add products to today’s sale',
            body: Center(child: FulusLoadingIndicator()),
          );
        }
        if (locationSnapshot.hasError || !locationSnapshot.hasData || locationSnapshot.data!.isEmpty) {
          return FulusScreen(
            title: 'Sell',
            subtitle: 'Add products to today’s sale',
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
      subtitle: 'Add products to today’s sale',
      actions: [
        FulusIconButton(icon: Icons.qr_code_scanner_outlined, tooltip: 'Scan product', onPressed: onScan),
        FulusIconButton(icon: Icons.storefront_outlined, tooltip: 'Quick Sale', onPressed: () => QuickSaleSheet.show(context)),
      ],
      applyPadding: false,
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state is CartFailure) return FulusErrorState(message: state.message, onRetry: onRetry);
          if (state is! CartLoaded) return const FulusLoadingIndicator();
          final inset = fulusHorizontalInset(context);
          final categoryIds = state.catalog.values.map((entry) => entry.product.categoryId).whereType<String>().toSet().toList()..sort((a, b) => (categoryById[a]?.name ?? a).compareTo(categoryById[b]?.name ?? b));
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
                child: FulusSearchField(controller: searchController, hintText: 'Search products or scan barcode', onChanged: onQueryChanged),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  scrollDirection: Axis.horizontal,
                  children: [
                    FulusChip(label: 'All', selected: selectedCategoryId == null, onTap: () => onCategoryChanged(null)),
                    for (final id in categoryIds)
                      FulusChip(
                        label: categoryById[id]?.name ?? id,
                        selected: selectedCategoryId == id,
                        onTap: () => onCategoryChanged(id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: _ProductList(state: state, query: query, categoryId: selectedCategoryId, onClearSearch: onClearSearch)),
              if (state.items.isNotEmpty) _CartSummaryBar(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.state, required this.query, required this.categoryId, required this.onClearSearch});

  final CartLoaded state;
  final String query;
  final String? categoryId;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final products = state.catalog.values.where((entry) {
      final p = entry.product;
      if (categoryId != null && p.categoryId != categoryId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q) || (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList()..sort((a, b) => a.product.name.compareTo(b.product.name));

    if (products.isEmpty) {
      return FulusEmptyState(
        headline: 'No products found',
        body: q.isEmpty ? 'Add products from Stock to start selling.' : 'Nothing matches “$query”.',
        icon: Icons.search_off,
        actionLabel: q.isEmpty ? 'Quick Sale' : 'Clear search',
        onAction: q.isEmpty ? () => QuickSaleSheet.show(context) : onClearSearch,
      );
    }

    final inset = fulusHorizontalInset(context);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xl),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) => _ProductRow(entry: products[index], currency: state.currencySymbol),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.entry, required this.currency});

  final ProductWithStock entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final product = entry.product;
    final out = product.tracksStock && entry.currentStock <= 0;
    final initial = product.name.trim().isEmpty ? '?' : product.name.trim()[0].toUpperCase();
    return FulusCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              width: 52,
              height: 52,
              color: AppColors.selectedTintOf(context),
              alignment: Alignment.center,
              child: product.photoPath == null
                  ? Text(initial, style: AppTypography.buttonLabel.copyWith(color: AppColors.primaryOf(context)))
                  : Image.file(
                      File(product.photoPath!),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, __, ___) => Text(initial, style: AppTypography.buttonLabel.copyWith(color: AppColors.primaryOf(context))),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
                const SizedBox(height: 3),
                Text('$currency${product.sellingPrice.toStringAsFixed(2)}', style: AppTypography.caption.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w600)),
                if (out) Text('Out of stock', style: AppTypography.caption.copyWith(color: AppColors.errorOf(context))),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FulusIconButton(icon: Icons.add, tooltip: out ? 'Out of stock' : 'Add ${product.name}', onPressed: out ? null : () => _add(context)),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    try {
      await context.read<CartCubit>().addProduct(entry.product.localId);
      FulusHaptics.selection();
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.sm),
        child: FulusButton(
          label: state.itemCount == 1
              ? 'View cart · 1 item · ${state.currencySymbol}${state.total.toStringAsFixed(2)}'
              : 'View cart · ${state.itemCount} items · ${state.currencySymbol}${state.total.toStringAsFixed(2)}',
          onPressed: () {
            final cubit = context.read<CartCubit>();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(value: cubit, child: const CartScreen()),
              ),
            );
          },
        ),
      ),
    );
  }
}
