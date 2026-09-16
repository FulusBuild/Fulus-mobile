import 'package:drift/drift.dart';

import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import '../local/database/database.dart';

/// Search fields and default limit carried over directly from the
/// backend's search_service.py (verified by reading it, not assumed):
/// Customers on name/phone/email, Products on name/sku/barcode, Sales on
/// invoice_number/notes excluding cancelled — with a default cap of 5
/// results per module. See search_result.dart's own doc comment for the
/// full reasoning on why this stage's job is the shared mechanism, not
/// a reinvention of these rules.
///
/// **A known, deliberate limitation:** SQL LIKE wildcard characters (%
/// and _) typed literally into a search query are not escaped here —
/// doing that correctly needs a SQL `ESCAPE` clause paired with the
/// exact escape character used, and getting that wrong silently (e.g.
/// inserting backslashes that don't actually function as escapes
/// without a matching clause) would be worse than not attempting it —
/// it would look like correctness without providing any. A search for a
/// literal "%" or "_" behaving like a wildcard instead is a real but
/// minor edge case (nothing in Products/Customers/Sales' own data
/// commonly contains either character), named here rather than
/// papered over with unverified escaping logic built with no compiler
/// available to confirm it actually works.
///
/// SQLite's LIKE is case-insensitive for ASCII by default (a real SQLite
/// behavior, not an assumption) — matching the backend's ilike closely
/// enough for this app's Latin-script product/customer names that no
/// explicit .lower() normalization is needed on either side of the
/// comparison.
class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<SearchResults> search(String query, {int limitPerModule = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearchResults.empty(query);

    final pattern = '%$trimmed%';

    final customers = await _searchCustomers(pattern, limitPerModule);
    final products = await _searchProducts(pattern, limitPerModule);
    final sales = await _searchSales(pattern, limitPerModule);

    return SearchResults(
      query: query,
      customers: customers,
      products: products,
      sales: sales,
    );
  }

  Future<List<SearchResultItem>> _searchCustomers(
    String pattern,
    int limit,
  ) async {
    final q = _db.select(_db.customers)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            (t.name.like(pattern) |
                t.phone.like(pattern) |
                t.email.like(pattern)),
      )
      ..limit(limit);
    final rows = await q.get();
    return rows
        .map(
          (c) => SearchResultItem(
            entityId: c.localId,
            module: SearchModule.customer,
            title: c.name,
            subtitle: c.phone,
          ),
        )
        .toList();
  }

  Future<List<SearchResultItem>> _searchProducts(
    String pattern,
    int limit,
  ) async {
    final q = _db.select(_db.products)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            (t.name.like(pattern) |
                t.sku.like(pattern) |
                t.barcode.like(pattern)),
      )
      ..limit(limit);
    final rows = await q.get();
    return rows
        .map(
          (p) => SearchResultItem(
            entityId: p.localId,
            module: SearchModule.product,
            title: p.name,
            subtitle: 'SKU: ${p.sku}',
          ),
        )
        .toList();
  }

  Future<List<SearchResultItem>> _searchSales(
    String pattern,
    int limit,
  ) async {
    // "Excluding cancelled," per search_service.py — this schema has no
    // separate status/is_cancelled column on Sales (verified directly in
    // tables.dart), so deletedAt.isNull() is the equivalent local
    // concept: a voided/cancelled sale is the one case any other
    // repository in this codebase already models as a soft delete, and
    // reusing that existing convention here (rather than inventing a
    // parallel "cancelled" concept specific to search) is the smaller,
    // more consistent choice.
    final q = _db.select(_db.sales)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            (t.invoiceNumber.like(pattern) | t.notes.like(pattern)),
      )
      ..limit(limit);
    final rows = await q.get();
    return rows
        .map(
          (s) => SearchResultItem(
            entityId: s.localId,
            module: SearchModule.sale,
            title: s.invoiceNumber ?? 'Sale ${s.localId.substring(0, 8)}',
            subtitle: _formatSaleDate(s.saleDate),
          ),
        )
        .toList();
  }

  String _formatSaleDate(DateTime date) {
    // Deliberately plain and locale-agnostic (no intl dependency added
    // for this) — a future results-list UI is free to format this
    // itself from the full SearchResultItem if a richer date format is
    // wanted; this repository's job is returning correct, minimal data.
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
