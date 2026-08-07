/// **Phase 0 completion pass.** Product Design Bible Volume 6, "Bulk
/// Import" — the CSV path (up to 200 rows; the second, camera-based
/// path the same section describes is a later, AI-adjacent capability,
/// not this one). Mirrors backend/app/schemas/import_schemas.py's
/// ImportResult/ImportRowError shape and
/// backend/app/services/import_service.py's import_products row rules
/// exactly — verified directly against both — but this is a from-scratch
/// Dart implementation, not a port: nothing here imports or calls
/// Python.
library;

/// One row-level problem. [field] is null for a whole-file problem
/// (currently only "a required column header is missing entirely" —
/// see [ProductImportPlan.headerErrors]), matching the backend's own
/// `row=0` convention for that case, just as a dedicated list instead
/// of a sentinel row number.
class ProductImportRowError {
  const ProductImportRowError({
    required this.row,
    this.field,
    required this.message,
  });

  /// 1-indexed against the *data* rows (the header row itself is never
  /// row 1 here) — deliberately NOT the backend's own `start=2`
  /// spreadsheet-line-number convention (which counts the header as
  /// row 1), since this type has nowhere to carry "which numbering
  /// convention" alongside it and a future screen showing these errors
  /// should decide its own display offset explicitly rather than
  /// inherit one silently from this layer.
  final int row;
  final String? field;
  final String message;
}

/// One row that passed every validation rule and is ready to become a
/// [Product] — still carrying [categoryName]/[supplierName] as raw
/// text rather than resolved ids, because resolving (and possibly
/// creating) a Category/Supplier by name is a database operation this
/// type deliberately has no part in; ImportProductsFromCsv (not
/// ProductImportEngine) does that resolution, using
/// CategoryRepository/SupplierRepository exactly as any other caller
/// of those would.
class ValidatedProductImportRow {
  const ValidatedProductImportRow({
    required this.row,
    required this.name,
    required this.sku,
    this.barcode,
    this.categoryName,
    this.supplierName,
    required this.costPrice,
    required this.sellingPrice,
    required this.lowStockThreshold,
    required this.initialStock,
  });

  final int row;
  final String name;
  final String sku;
  final String? barcode;
  final String? categoryName;
  final String? supplierName;
  final double costPrice;
  final double sellingPrice;
  final int lowStockThreshold;
  final int initialStock;
}

/// ProductImportEngine's pure output — what CAN be created, plus every
/// reason something couldn't be. Deliberately doesn't say whether
/// anything was actually created; that's [ProductImportResult]'s job,
/// once ImportProductsFromCsv has actually acted on this plan.
class ProductImportPlan {
  const ProductImportPlan({
    required this.rowsToCreate,
    required this.rowErrors,
    required this.headerErrors,
    required this.totalRows,
  });

  final List<ValidatedProductImportRow> rowsToCreate;
  final List<ProductImportRowError> rowErrors;

  /// Non-empty only when a required column (name/sku/selling_price) is
  /// missing from the file entirely — mirrors the backend's own
  /// immediate, whole-file rejection in that case (import_service.py's
  /// `_require_headers` check) rather than reporting every row as
  /// individually broken.
  final List<ProductImportRowError> headerErrors;
  final int totalRows;

  bool get isRejected => headerErrors.isNotEmpty;
}

/// What ImportProductsFromCsv returns once it's actually tried to
/// create every row [ProductImportPlan.rowsToCreate] named — a
/// createProduct call can still fail for a reason validation can't see
/// in advance (this device's own local database rejecting something),
/// so successCount can be lower than rowsToCreate.length even after a
/// plan with zero validation errors.
class ProductImportResult {
  const ProductImportResult({
    required this.successCount,
    required this.errorCount,
    required this.totalRows,
    required this.errors,
    required this.createdProductLocalIds,
  });

  final int successCount;
  final int errorCount;
  final int totalRows;
  final List<ProductImportRowError> errors;
  final List<String> createdProductLocalIds;
}
