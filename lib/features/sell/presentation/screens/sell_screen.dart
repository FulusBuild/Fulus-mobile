import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/design_tokens.dart';
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
      backgroundColor: const Color(0xFF061B3A),
      headerBackgroundColor: const Color(0xFF061B3A),
      applyPadding: false,
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state is CartFailure) return FulusErrorState(message: state.message, onRetry: onRetry);
          if (state is! CartLoaded) return const FulusLoadingIndicator();
          final inset = fulusHorizontalInset(context);
          final categoryIds = state.catalog.values.map((entry) => entry.product.categoryId).whereType<String>().toSet().toList()
            ..sort((a, b) => (categoryById[a]?.name ?? a).compareTo(categoryById[b]?.name ?? b));
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.15;
                    final scanButton = FulusButton(
                      variant: FulusButtonVariant.secondary,
                      foregroundColor: Colors.white,
                      borderColor: Colors.white70,
                      icon: FulusIcons.scan,
                      label: 'Scan',
                      onPressed: onScan,
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
              Expanded(
                child: _ProductList(
                  state: state,
                  query: query,
                  categoryId: selectedCategoryId,
                  onClearSearch: onClearSearch,
                ),
              ),
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
        icon: FulusIcons.search,
        actionLabel: q.isEmpty ? 'Quick Sale' : 'Clear search',
        onAction: q.isEmpty ? () => QuickSaleSheet.show(context) : onClearSearch,
      );
    }

    final inset = fulusHorizontalInset(context);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.sm, inset, AppSpacing.xl),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(