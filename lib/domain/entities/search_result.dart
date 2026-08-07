import 'package:equatable/equatable.dart';

/// Stage 14 (Search half) — Global Search.
///
/// No Product Design Bible volume specifies global cross-entity search
/// as its own experience the way Volume 12 specifies sync or Volume 11
/// specifies Settings — "Search" appears inside Volume 5 ("Finding
/// Products," in-cart product search) and inside Volume 5's Refunds flow
/// ("searches recent receipts by number, customer, or a short
/// recent-sales list"). What Stage 14 names as its own roadmap item is
/// the shared, reusable SEARCH INFRASTRUCTURE those (and future) features
/// call into, rather than each feature re-implementing its own ad-hoc
/// filter — the same "one mechanism, several callers" shape Volume 10
/// already specifies for Export ("Exports extend the same CSV/PDF
/// mechanism... rather than inventing a separate export path per
/// category").
///
/// The shape and matched fields below are carried over directly from the
/// backend's own search_service.py (global_search) — verified by reading
/// it directly rather than assumed — which searches Customers
/// (name/phone/email), Products (name/sku/barcode), and Sales
/// (invoice_number/notes, excluding cancelled). Employees is a fourth
/// category there; not reproduced here because no Employees repository
/// exists yet in this codebase (Stage 11, not yet built — see
/// HANDOVER-2.md) — SearchModule below is deliberately open to adding it
/// (and Expenses/Income, which the backend's search doesn't even cover)
/// the moment that repository lands, without restructuring this type.
enum SearchModule { customer, product, sale }

/// One matched record, already reduced to exactly what a search results
/// list needs to render and let the user act on — never the full entity.
/// (A screen that needs the full Customer/Product/Sale after a tap
/// re-fetches it by [entityId] from the relevant repository — this type
/// is a search-results-list projection, not a substitute for those
/// repositories.)
class SearchResultItem extends Equatable {
  const SearchResultItem({
    required this.entityId,
    required this.module,
    required this.title,
    this.subtitle,
  });

  /// The matched record's own localId — NOT this result's own identity
  /// (SearchResultItem has none; it's a transient projection, never
  /// stored).
  final String entityId;

  final SearchModule module;

  /// The primary matched text — a customer's name, a product's name, a
  /// sale's invoice number.
  final String title;

  /// A short secondary line, module-specific (a customer's phone; a
  /// product's SKU and stock; a sale's total and payment status) — built
  /// by SearchRepositoryImpl (data/repositories/search_repository_impl.dart),
  /// which is where the exact per-module formatting choices are made and
  /// justified.
  final String? subtitle;

  @override
  List<Object?> get props => [entityId, module, title, subtitle];
}

/// The grouped, capped result set for one query — mirrors
/// search_service.py's SearchResponse shape (grouped per module, plus a
/// combined flat list) directly, since a results-overlay UI plausibly
/// wants both: module-labeled sections, and a total count.
class SearchResults extends Equatable {
  const SearchResults({
    required this.query,
    required this.customers,
    required this.products,
    required this.sales,
  });

  const SearchResults.empty(String query)
      : this(query: query, customers: const [], products: const [], sales: const []);

  final String query;
  final List<SearchResultItem> customers;
  final List<SearchResultItem> products;
  final List<SearchResultItem> sales;

  int get total => customers.length + products.length + sales.length;

  List<SearchResultItem> get all => [...customers, ...products, ...sales];

  @override
  List<Object?> get props => [query, customers, products, sales];
}
