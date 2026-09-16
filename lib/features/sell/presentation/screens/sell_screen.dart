import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/design_tokens.dart';
import '../../../../core/ux/consumer_polish.dart';
import '../../../../domain/entities/product.dart';
import '../../../../shared/widgets/widgets.dart';
import '../cubit/cart_cubit.dart';
import '../cubit/cart_state.dart';
import '../widgets/quick_sale_sheet.dart';
import 'cart_screen.dart';

class SellScreen extends StatefulWidget {
  const SellScreen({super.key});
  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategoryId;

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }
  void _clearSearch() { _searchController.clear(); setState(() => _query = ''); }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sell',
      subtitle: 'Add products to today’s sale',
      actions: [
        FulusIconButton(icon: Icons.qr_code_scanner_outlined, tooltip: 'Scan product', onPressed: () {}),
        FulusIconButton(icon: Icons.storefront_outlined, tooltip: 'Quick Sale', onPressed: () => QuickSaleSheet.show(context)),
      ],
      body: BlocBuilder<CartCubit, CartState>(
        builder: (context, state) {
          if (state is CartFailure) return FulusErrorState(message: state.message);
          if (state is! CartLoaded) return const FulusLoadingIndicator();
          final inset = fulusHorizontalInset(context);
          return Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.sm),
              child: FulusSearchField(controller: _searchController, hintText: 'Search products or scan barcode', onChanged: (value) => setState(() => _query = value)),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: inset),
                scrollDirection: Axis.horizontal,
                children: [
                  FulusChip(label: 'All', selected: _selectedCategoryId == null, onTap: () => setState(() => _selectedCategoryId = null)),
                  ...state.catalog.values.map((entry) => entry.product.categoryId).whereType<String>().toSet().map(
                    (id) => FulusChip(label: id, selected: _selectedCategoryId == id, onTap: () => setState(() => _selectedCategoryId = id)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(child: _ProductList(state: state, query: _query, categoryId: _selectedCategoryId, onClearSearch: _clearSearch)),
            if (state.items.isNotEmpty) _CartSummaryBar(state: state),
          ]);
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
    return FulusCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: AppColors.selectedTintOf(context), borderRadius: BorderRadius.circular(AppRadius.md)),
          alignment: Alignment.center,
          child: Icon(Icons.inventory_2_outlined, color: AppColors.primaryOf(context)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: 3),
          Text('$currency${product.sellingPrice.toStringAsFixed(2)}', style: AppTypography.caption.copyWith(color: AppColors.primaryOf(context), fontWeight: FontWeight.w600)),
          if (out) Text('Out of stock', style: AppTypography.caption.copyWith(color: AppColors.errorOf(context))),
        ])),
        const SizedBox(width: AppSpacing.sm),
        FulusIconButton(icon: Icons.add, tooltip: out ? 'Out of stock' : 'Add ${product.name}', onPressed: out ? null : () => _add(context)),
      ]),
    );
  }

  Future<void> _add(BuildContext context) async {
    try {
      await context.read<CartCubit>().addProduct(entry);
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(fulusHorizontalInset(context), AppSpacing.sm, fulusHorizontalInset(context), AppSpacing.sm),
        child: FulusButton(
          label: state.itemCount == 1 ? 'View cart · 1 item · ${state.currencySymbol}${state.total.toStringAsFixed(2)}' : 'View cart · ${state.itemCount} items · ${state.currencySymbol}${state.total.toStringAsFixed(2)}',
          onPressed: () {
            final cubit = context.read<CartCubit>();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlocProvider.value(value: cubit, child: const CartScreen())));
          },
        ),
      ),
    );
  }
}
