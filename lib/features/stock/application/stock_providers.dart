import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // for StateProvider.autoDispose

import '../../../app/providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_movement.dart';
import '../../../domain/entities/supplier.dart';

/// The location Stock's data is scoped to — the same app-wide
/// resolution every feature uses now (`app/providers.dart`'s
/// `activeLocationIdProvider`, backed by `ResolveActiveLocation`),
/// replacing what used to be this file's own hardcoded fallback.
///
/// CORRECTED: this provider used to fall back to a constant
/// (`kStockFallbackLocationId = 'local-default'`) that was never
/// actually written to the Locations table — a real, confirmed gap
/// this screen ran into while being built: `Location` was, at the
/// time, explicitly "business-wide, desktop-managed... not something a
/// mobile device creates," and nothing anywhere in the app — not
/// bootstrap, not owner setup — ever seeded one. A genuinely
/// mobile-only business had zero rows in Locations, and this Stock
/// screen's own StockMovements/DraftCarts records would have carried a
/// locationId (`'local-default'`) that pointed at nothing in the
/// database. That gap is closed now (`LocationRepository.
/// getOrCreateDefaultLocation`, `ResolveActiveLocation`,
/// `owner_setup_screen.dart` seeding one at onboarding) — this provider
/// just delegates to the same resolver every other feature does.
///
/// Kept under this name (rather than renaming every call site in this
/// feature to `activeLocationIdProvider` directly) purely so
/// stock_screen.dart / product_detail_screen.dart /
/// stock_movement_history_screen.dart / record_stock_movement_screen.dart
/// / add_edit_product_screen.dart need no changes of their own.
final currentLocationIdProvider = activeLocationIdProvider;

/// All products at the current location, stock-joined — the shape
/// every Stock screen actually needs (see [ProductWithStock]'s own doc
/// comment). `.family` keyed by locationId rather than reading
/// [currentLocationIdProvider] internally, so a screen that already has
/// a resolved locationId (e.g. after the location stream has settled)
/// can watch this directly without re-deriving it.
final productsWithStockProvider =
    StreamProvider.autoDispose.family<List<ProductWithStock>, String>((ref, locationId) {
  return ref.watch(productRepositoryProvider).watchProducts(locationId: locationId);
});

final lowStockProductsProvider =
    StreamProvider.autoDispose.family<List<ProductWithStock>, String>((ref, locationId) {
  return ref.watch(productRepositoryProvider).watchLowStockProducts(locationId: locationId);
});

final categoriesProvider = StreamProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchCategories();
});

/// Volume 6: "A supplier is a name, a phone number, and an optional
/// note." Used here only for Stock In's optional supplier field and the
/// Add Product form's "More details" — a full supplier-management
/// screen (edit/delete, the ledger referenced in Volume 8) is out of
/// scope for Stock specifically.
final suppliersProvider = StreamProvider.autoDispose<List<Supplier>>((ref) {
  return ref.watch(supplierRepositoryProvider).watchSuppliers();
});

/// Every movement at the current location — Stock In/Out/Adjustment
/// entries a user submitted here, and (once Sell exists to create them)
/// `.sale`-type rows too, automatically: a sale's stock decrease is
/// already unified into this same ledger at the data layer
/// (stock_movement.dart's own doc comment on [StockMovementType.sale]),
/// so this feed doesn't need its own separate integration with
/// SaleRepository to show "what recently changed" completely — it's
/// already complete by construction, forward-compatible with a Sell
/// feature that doesn't exist yet.
final stockMovementsProvider =
    StreamProvider.autoDispose.family<List<StockMovement>, String>((ref, locationId) {
  return ref.watch(stockMovementRepositoryProvider).watchMovementsForLocation(locationId);
});

/// Sort options for the product list — 5.13-style short list, not a
/// dedicated component: only ever reachable from one bottom sheet on
/// this screen.
enum StockSortOrder { nameAsc, stockLowToHigh, stockHighToLow, valueHighToLow }

extension StockSortOrderLabel on StockSortOrder {
  String get label => switch (this) {
        StockSortOrder.nameAsc => 'Name (A–Z)',
        StockSortOrder.stockLowToHigh => 'Stock: low to high',
        StockSortOrder.stockHighToLow => 'Stock: high to low',
        StockSortOrder.valueHighToLow => 'Value: high to low',
      };
}

/// Search + category + low-stock-only + sort, combined — one piece of
/// UI state rather than four separate providers, since every control on
/// the Stock screen reads and writes this together.
class StockFilterState {
  const StockFilterState({
    this.query = '',
    this.categoryId,
    this.lowStockOnly = false,
    this.outOfStockOnly = false,
    this.sort = StockSortOrder.nameAsc,
  });

  final String query;

  /// Null means "All categories."
  final String? categoryId;
  final bool lowStockOnly;
  final bool outOfStockOnly;
  final StockSortOrder sort;

  bool get isDefault =>
      query.isEmpty && categoryId == null && !lowStockOnly && !outOfStockOnly && sort == StockSortOrder.nameAsc;

  StockFilterState copyWith({
    String? query,
    Object? categoryId = _unset,
    bool? lowStockOnly,
    bool? outOfStockOnly,
    StockSortOrder? sort,
  }) {
    return StockFilterState(
      query: query ?? this.query,
      categoryId: identical(categoryId, _unset) ? this.categoryId : categoryId as String?,
      lowStockOnly: lowStockOnly ?? this.lowStockOnly,
      outOfStockOnly: outOfStockOnly ?? this.outOfStockOnly,
      sort: sort ?? this.sort,
    );
  }
}

const _unset = Object();

final stockFilterProvider = StateProvider.autoDispose<StockFilterState>((ref) => const StockFilterState());

/// Pure — applies search, category, low-stock-only, and sort to a raw
/// product list. A plain function rather than another provider layer:
/// nothing here is async, so there's nothing a provider adds over
/// calling this directly from build() with values already in hand from
/// [productsWithStockProvider]/[stockFilterProvider].
List<ProductWithStock> applyStockFilter(List<ProductWithStock> products, StockFilterState filter) {
  var result = products.where((p) => p.product.isActive).toList();
  // (isActive check above is a no-op guard kept explicit rather than
  // omitted — watchProducts's own query already excludes deleted/
  // inactive rows, but a list screen silently trusting that with no
  // local check of its own is exactly the kind of assumption worth
  // making visible rather than implicit.)

  if (filter.query.trim().isNotEmpty) {
    final q = filter.query.trim().toLowerCase();
    result = result.where((p) {
      final name = p.product.name.toLowerCase();
      final sku = p.product.sku.toLowerCase();
      final barcode = p.product.barcode?.toLowerCase() ?? '';
      return name.contains(q) || sku.contains(q) || barcode.contains(q);
    }).toList();
  }

  if (filter.categoryId != null) {
    result = result.where((p) => p.product.categoryId == filter.categoryId).toList();
  }

  if (filter.lowStockOnly) {
    result = result.where((p) => p.isLowStock).toList();
  }

  if (filter.outOfStockOnly) {
    result = result.where((p) => p.product.tracksStock && p.currentStock <= 0).toList();
  }

  switch (filter.sort) {
    case StockSortOrder.nameAsc:
      result.sort((a, b) => a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()));
      break;
    case StockSortOrder.stockLowToHigh:
      result.sort((a, b) => a.currentStock.compareTo(b.currentStock));
      break;
    case StockSortOrder.stockHighToLow:
      result.sort((a, b) => b.currentStock.compareTo(a.currentStock));
      break;
    case StockSortOrder.valueHighToLow:
      result.sort((a, b) => _stockValue(b).compareTo(_stockValue(a)));
      break;
  }
  return result;
}

/// Cost-basis value — Volume 6 lists Cost Price as the field that
/// "enables margin reporting," which is the closest the Bible comes to
/// stating what stock value should be measured against; cost is also
/// the conventional inventory-accounting basis (what was actually paid,
/// vs. selling price, which is potential revenue, not asset value).
/// [ProductResponseDto.stockValue] exists on the backend's wire format,
/// but its exact formula isn't visible from the DTO alone, so this is
/// this screen's own best-supported reading, not a confirmed match to
/// a backend calculation this device can't see.
double _stockValue(ProductWithStock p) => p.product.costPrice * p.currentStock;

double totalStockValue(List<ProductWithStock> products) =>
    products.where((p) => p.product.tracksStock).fold(0.0, (sum, p) => sum + _stockValue(p));

int outOfStockCount(List<ProductWithStock> products) =>
    products.where((p) => p.product.tracksStock && p.currentStock <= 0).length;
