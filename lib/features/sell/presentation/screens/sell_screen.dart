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
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _locationIdFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FulusScreen(title: 'Sell', body: FulusErrorState(message: "Couldn't open Sell.", reassurance: 'Nothing was sold or lost — this is only about loading the screen.', onRetry: () => setState(() => _locationIdFuture = _resolveLocationId())));
          }
          if (!snapshot.hasData) return const FulusScreen(title: 'Sell', body: FulusLoadingIndicator());
          return BlocProvider(
            create: (_) => CartCubit(
              draftCartRepository: ref.read(draftCartRepositoryProvider),
              productRepository: ref.read(productRepositoryProvider),
              customerRepository: ref.read(customerRepositoryProvider),
              businessSettingsRepository: ref.read(businessSettingsRepositoryProvider),
              locationId: snapshot.data!,
              diagnosticLogger: ref.read(diagnosticLoggerProvider),
            ),
            child: const _SellBody(),
          );
        },
      );
}

class _SellBody extends ConsumerStatefulWidget {
  const _SellBody();
  @override
  ConsumerState<_SellBody> createState() => _SellBodyState();
}

class _SellBodyState extends ConsumerState<_SellBody> {
  final _searchController = TextEditingController();
  late final Stream<List<Category>> _categoriesStream = ref.read(categoryRepositoryProvider).watchCategories();
  static const _favoritesKey = 'fulus_sell_favorite_product_ids';
  final Set<String> _favoriteIds = {};
  String _query = '';
  String? _categoryId;
  bool _favoritesOnly = false;
  bool _favoritesLoaded = false;

  @override
  void initState() { super.initState(); _loadFavorites(); }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() { _favoriteIds..clear()..addAll(prefs.getStringList(_favoritesKey) ?? const []); _favoritesLoaded = true; });
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() => _favoriteIds.contains(id) ? _favoriteIds.remove(id) : _favoriteIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() { _query = ''; _categoryId = null; _favoritesOnly = false; });
  }

  Future<void> _add(BuildContext context, ProductWithStock item) async {
    try { await context.read<CartCubit>().addProduct(item.product.localId); if (context.mounted) FulusHaptics.selection(); }
    on StateError catch (e) { FulusHaptics.error(); if (context.mounted) showFulusSnackbar(context, message: e.message); }
  }

  Future<void> _scan(BuildContext context) async {
    final barcode = await BarcodeScanScreen.scan(context, title: 'Scan a product');
    if (barcode == null || !context.mounted) return;
    final state = context.read<CartCubit>().state;
    if (state is! CartLoaded) return;
    ProductWithStock? match;
    for (final item in state.catalog.values) { if (item.product.barcode == barcode) { match = item; break; } }
    if (match == null) {
      showFulusSnackbar(context, message: 'No product found with that barcode.', actionLabel: 'Quick Sale', onAction: () => QuickSaleSheet.show(context));
      return;
    }
    await _add(context, match);
    if (context.mounted) showFulusSnackbar(context, message: '${match.product.name} added');
  }

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FulusScreen(
      title: 'Sell', applyPadding: false,
      actions: [
        FulusIconButton(icon: Icons.qr_code_scanner_outlined, tooltip: 'Scan a barcode', onPressed: () => _scan(context)),
        FulusIconButton(icon: Icons.assignment_return_outlined, tooltip: 'Refund a sale', onPressed: () => context.pushNamed('sellRefundSearch')),
        FulusIconButton(icon: Icons.storefront_outlined, tooltip: 'Quick Sale', onPressed: () => QuickSaleSheet.show(context)),
      ],
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm), child: FulusSearchField(controller: _searchController, hintText: 'Search products…', autofocus: true, onChanged: (v) => setState(() => _query = v))),
        Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm), child: FulusChipRow(children: [
          FulusChip(label: 'All', selected: !_favoritesOnly, onTap: () => setState(() => _favoritesOnly = false)),
          FulusChip(label: 'Favorites', selected: _favoritesOnly, onTap: () => setState(() => _favoritesOnly = true)),
        ])),
        StreamBuilder<List<Category>>(
          stream: _categoriesStream,
          builder: (context, snapshot) {
            final categories = snapshot.data ?? const <Category>[];
            if (categories.isEmpty) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm), child: FulusChipRow(children: [
              FulusChip(label: 'All categories', selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
              for (final category in categories) FulusChip(label: category.name, selected: _categoryId == category.localId, onTap: () => setState(() => _categoryId = category.localId)),
            ]));
          },
        ),
        Expanded(child: BlocSelector<CartCubit, CartState, _CatalogView?>(
          selector: (state) => state is CartLoaded ? (catalog: state.catalog, loaded: state.catalogLoaded, currency: state.currencySymbol) : null,
          builder: (context, view) {
            if (view == null) {
              final state = context.read<CartCubit>().state;
              if (state is CartFailure) return FulusErrorState(message: state.message);
              return const FulusLoadingIndicator();
            }
            return _CatalogList(view: view, query: _query, categoryId: _categoryId, favoritesOnly: _favoritesOnly, favoriteIds: _favoriteIds, favoritesLoaded: _favoritesLoaded, onAdd: (p) => _add(context, p), onFavorite: _toggleFavorite, onClear: _clearFilters);
          },
        )),
        BlocBuilder<CartCubit, CartState>(builder: (context, state) => state is CartLoaded && state.items.isNotEmpty ? _CartBar(state: state) : const SizedBox.shrink()),
      ]),
    );
  }
}

typedef _CatalogView = ({Map<String, ProductWithStock> catalog, bool loaded, String currency});

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.view, required this.query, required this.categoryId, required this.favoritesOnly, required this.favoriteIds, required this.favoritesLoaded, required this.onAdd, required this.onFavorite, required this.onClear});
  final _CatalogView view; final String query; final String? categoryId; final bool favoritesOnly; final Set<String> favoriteIds; final bool favoritesLoaded;
  final Future<void> Function(ProductWithStock) onAdd; final Future<void> Function(String) onFavorite; final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (!view.loaded || !favoritesLoaded) return ListView.separated(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl), itemCount: 6, separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm), itemBuilder: (_, __) => const FulusDelayedSkeleton(skeleton: FulusCardSkeleton()));
    final q = query.trim().toLowerCase();
    final products = view.catalog.values.where((item) {
      final p = item.product;
      if (favoritesOnly && !favoriteIds.contains(p.localId)) return false;
      if (categoryId != null && p.categoryId != categoryId) return false;
      return q.isEmpty || p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q) || (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList()..sort((a, b) { final fav = (favoriteIds.contains(b.product.localId) ? 1 : 0) - (favoriteIds.contains(a.product.localId) ? 1 : 0); return fav != 0 ? fav : a.product.name.compareTo(b.product.name); });
    if (view.catalog.isEmpty) return FulusEmptyState(headline: 'No products yet', body: "Add products from Stock once it's set up, or use Quick Sale for anything you're selling today.", icon: Icons.storefront_outlined, actionLabel: 'Quick Sale', onAction: () => QuickSaleSheet.show(context));
    if (products.isEmpty) return FulusEmptyState(headline: favoritesOnly ? 'No favorites yet' : 'No matches', body: favoritesOnly ? 'Star your fastest-selling products to keep them one tap away.' : q.isEmpty ? 'No products in this category yet.' : 'Nothing matches "$query" — try a different search, or use Quick Sale.', icon: favoritesOnly ? Icons.star_border : Icons.search_off, actionLabel: 'Clear filters', onAction: onClear);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxxl),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => FulusProductRow(productWithStock: products[i], currencySymbol: view.currency, isFavorite: favoriteIds.contains(products[i].product.localId), onAdd: () => onAdd(products[i]), onToggleFavorite: () => onFavorite(products[i].product.localId)),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.state});
  final CartLoaded state;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
        child: Material(
          color: AppColors.primaryOf(context), borderRadius: BorderRadius.circular(AppRadius.xl),
          child: FulusPressable(
            semanticsLabel: 'View cart, ${state.itemCount} ${state.itemCount == 1 ? 'item' : 'items'}',
            onPressed: () {
              final cubit = context.read<CartCubit>();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => BlocProvider.value(value: cubit, child: const CartScreen())));
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              child: Row(children: [
                Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.onPrimaryOf(context).withValues(alpha: .14), shape: BoxShape.circle), child: Text('${state.itemCount}', style: AppTypography.label.copyWith(color: AppColors.onPrimaryOf(context), fontWeight: FontWeight.w700))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Current sale', style: AppTypography.caption.copyWith(color: AppColors.onPrimaryOf(context).withValues(alpha: .72))),
                  Text(state.itemCount == 1 ? '1 item in cart' : '${state.itemCount} items in cart', style: AppTypography.buttonLabel.copyWith(color: AppColors.onPrimaryOf(context))),
                ])),
                Text(formatMoney(state.total, symbol: state.currencySymbol), style: AppTypography.mono.copyWith(color: AppColors.onPrimaryOf(context), fontWeight: FontWeight.w700)),
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.arrow_forward, color: AppColors.onPrimaryOf(context), size: AppIconSize.compact),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
