import 'dart:math';

import '../entities/product_import.dart';

/// **Phase 0 completion pass.** Pure business logic — no database, no
/// Flutter, same isolation every other file in this folder and in
/// core/business_engine/ already holds itself to. Validates and parses
/// CSV rows already split into header-keyed maps (CsvParser's job, not
/// this class's); this class's only job is deciding what's valid and
/// computing the numbers, mirroring
/// backend/app/services/import_service.py's import_products row rules
/// exactly (verified directly), including two easy-to-miss ones:
/// column matching is case-insensitive, and a row with an invalid
/// selling_price does NOT also get a separate "required" error on top
/// of the "not a valid number" one — only a genuinely *blank*
/// selling_price with no other error on the row gets that message,
/// which needs the same two-step "try to parse; then, only if nothing
/// else already complained, check for missing" logic the backend uses,
/// not a simpler `if blank: error` that would double up on invalid input.
class ProductImportEngine {
  const ProductImportEngine();

  // UX fix: 'sku' used to be required here even though
  // AddEditProductScreen (the single-product path) never asks a person
  // for one at all — it generates one internally (see that screen's own
  // `_generateSku`). Requiring it here forced anyone doing a bulk
  // import to invent SKU codes for a field the rest of the app treats
  // as invisible plumbing, with no explanation of what it even is.
  // 'sku' is now optional per-row instead — see the generation branch
  // in [validate] below.
  static const _requiredHeaders = ['name', 'selling_price'];

  /// Header-only check, deliberately split out from [validate] so a
  /// caller (ImportProductsFromCsv) can reject a bad file before doing
  /// anything that needs a database round-trip (existingSkus/
  /// existingBarcodes) — a file missing a required column should never
  /// touch a repository at all. Returns null when every required
  /// header is present.
  ProductImportRowError? validateHeaders(List<String> headers) {
    final lowerHeaders = headers.map((h) => h.toLowerCase()).toSet();
    final missing = _requiredHeaders.where((h) => !lowerHeaders.contains(h)).toList();
    if (missing.isEmpty) return null;
    return ProductImportRowError(
      row: 0,
      message: 'Missing required column(s): ${missing.join(', ')}.',
    );
  }

  /// [existingSkus] must be exact-match, case-sensitive — matches the
  /// backend's own bare `sku in existing_skus` (no `.lower()` there,
  /// unlike the category/supplier name matching ImportProductsFromCsv
  /// does downstream of this class). [existingBarcodes] is the same
  /// contract for the barcode-uniqueness check.
  ProductImportPlan validate({
    required List<String> headers,
    required List<Map<String, String>> rows,
    required Set<String> existingSkus,
    required Set<String> existingBarcodes,
  }) {
    final headerError = validateHeaders(headers);
    if (headerError != null) {
      return ProductImportPlan(
        rowsToCreate: const [],
        rowErrors: const [],
        headerErrors: [headerError],
        totalRows: 0,
      );
    }

    final toCreate = <ValidatedProductImportRow>[];
    final allErrors = <ProductImportRowError>[];
    // Within-file duplicates need their own tracking, separate from
    // existingSkus/existingBarcodes (already-in-the-database values) —
    // two rows in the SAME upload sharing a SKU would otherwise both
    // sail through the "not in existingSkus" check and both attempt to
    // create, since neither one is actually in the database yet at
    // validation time. The backend doesn't hit this: SQLAlchemy would
    // raise a unique-constraint error on the second INSERT, caught
    // nowhere in import_products, which would surface as an unhandled
    // 500 rather than a clean per-row error — not a gap worth
    // reproducing faithfully.
    final skusSeenThisFile = <String>{};
    final barcodesSeenThisFile = <String>{};

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      final rowErrors = <ProductImportRowError>[];

      final name = _field(row, 'name');
      var sku = _field(row, 'sku');

      if (name == null || name.isEmpty) {
        rowErrors.add(ProductImportRowError(row: rowNumber, field: 'name', message: 'Name is required.'));
      }

      if (sku != null && sku.isNotEmpty) {
        if (existingSkus.contains(sku) || skusSeenThisFile.contains(sku)) {
          rowErrors.add(ProductImportRowError(row: rowNumber, field: 'sku', message: "SKU '$sku' already exists."));
        }
      } else {
        // A row that leaves sku blank (or omits the column entirely)
        // gets one generated rather than rejected — see this class's
        // header comment and the `_requiredHeaders` comment above.
        sku = _generateSku(name ?? '', existingSkus, skusSeenThisFile);
      }

      final sellingPrice = _parseDouble(
        _field(row, 'selling_price'),
        field: 'selling_price',
        row: rowNumber,
        errors: rowErrors,
        minValue: 0,
      );
      if (sellingPrice == null && rowErrors.isEmpty) {
        rowErrors.add(
          ProductImportRowError(row: rowNumber, field: 'selling_price', message: 'Selling price is required.'),
        );
      }

      final barcode = _field(row, 'barcode');
      if (barcode != null &&
          barcode.isNotEmpty &&
          (existingBarcodes.contains(barcode) || barcodesSeenThisFile.contains(barcode))) {
        rowErrors.add(ProductImportRowError(row: rowNumber, field: 'barcode', message: "Barcode '$barcode' already exists."));
      }

      final costPrice = _parseDouble(
            _field(row, 'cost_price') ?? '0',
            field: 'cost_price',
            row: rowNumber,
            errors: rowErrors,
            minValue: 0,
          ) ??
          0.0;
      final initialStock = _parseInt(
            _field(row, 'initial_stock') ?? '0',
            field: 'initial_stock',
            row: rowNumber,
            errors: rowErrors,
            minValue: 0,
          ) ??
          0;
      final lowStockThreshold = _parseInt(
            _field(row, 'low_stock_threshold') ?? '10',
            field: 'low_stock_threshold',
            row: rowNumber,
            errors: rowErrors,
            minValue: 0,
          ) ??
          10;

      if (rowErrors.isNotEmpty) {
        allErrors.addAll(rowErrors);
        continue;
      }

      if (sku != null) skusSeenThisFile.add(sku);
      if (barcode != null && barcode.isNotEmpty) barcodesSeenThisFile.add(barcode);

      final categoryName = _field(row, 'category');
      final supplierName = _field(row, 'supplier');

      toCreate.add(ValidatedProductImportRow(
        row: rowNumber,
        name: name!,
        sku: sku!,
        barcode: (barcode == null || barcode.isEmpty) ? null : barcode,
        categoryName: (categoryName == null || categoryName.isEmpty) ? null : categoryName,
        supplierName: (supplierName == null || supplierName.isEmpty) ? null : supplierName,
        costPrice: costPrice,
        // Provably non-null here, not just defensively coerced: every
        // path that leaves sellingPrice null also leaves rowErrors
        // non-empty by this point (either the required-price error
        // itself, or an earlier name/sku error that suppressed it —
        // see this method's own doc comment), and any of those already
        // hit `continue` above.
        sellingPrice: sellingPrice!,
        lowStockThreshold: lowStockThreshold,
        initialStock: initialStock,
      ));
    }

    return ProductImportPlan(
      rowsToCreate: toCreate,
      rowErrors: allErrors,
      headerErrors: const [],
      totalRows: rows.length,
    );
  }

  /// Synchronous counterpart to AddEditProductScreen's own async
  /// `_generateSku` — same prefix + random-suffix shape, kept
  /// deliberately identical so a generated SKU looks the same whether
  /// it came from the single-product screen or a bulk import row.
  /// Checked against the sku sets this validation pass already holds in
  /// memory rather than a fresh repository round-trip per row, since
  /// [validate] has no repository access by design (see this class's
  /// own header comment).
  String _generateSku(String name, Set<String> existingSkus, Set<String> skusSeenThisFile) {
    final prefix = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '').padRight(3, 'X').substring(0, 3);
    final random = Random();
    for (var attempt = 0; attempt < 20; attempt++) {
      final suffix = (1000 + random.nextInt(9000)).toString();
      final candidate = '$prefix-$suffix';
      if (!existingSkus.contains(candidate) && !skusSeenThisFile.contains(candidate)) return candidate;
    }
    // Same reasoning as AddEditProductScreen's own fallback: 20
    // collisions against a 9000-value space won't happen in practice,
    // but this keeps the function total rather than assuming it.
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Case-insensitive column lookup — headers were already
  /// case-preserved by CsvParser, so a file with a `Selling_Price`
  /// column (capitalized differently than expected) still resolves
  /// correctly here, matching `_require_headers`' own `.lower()`
  /// comparison. Returns null (not empty string) for a genuinely
  /// absent or blank cell — callers use `??` for their own field-
  /// specific default rather than this method silently picking one.
  String? _field(Map<String, String> row, String key) {
    for (final entry in row.entries) {
      if (entry.key.toLowerCase() == key) {
        return entry.value.isEmpty ? null : entry.value;
      }
    }
    return null;
  }

  double? _parseDouble(
    String? value, {
    required String field,
    required int row,
    required List<ProductImportRowError> errors,
    double? minValue,
  }) {
    if (value == null) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) {
      errors.add(ProductImportRowError(row: row, field: field, message: "'$value' is not a valid number."));
      return null;
    }
    if (minValue != null && parsed < minValue) {
      errors.add(ProductImportRowError(row: row, field: field, message: "'$value' must be $minValue or greater."));
      return null;
    }
    return parsed;
  }

  /// Parses via double first, then truncates — matches the backend's
  /// own `int(float(value))`, which is deliberately more lenient than
  /// a strict integer parse: a spreadsheet cell holding "10.0" (an easy
  /// thing for a formula or a naive numeric-column formatter to
  /// produce) is accepted here rather than rejected the way
  /// `int.tryParse('10.0')` alone would reject it.
  int? _parseInt(
    String? value, {
    required String field,
    required int row,
    required List<ProductImportRowError> errors,
    int? minValue,
  }) {
    if (value == null) return null;
    final parsedDouble = double.tryParse(value);
    if (parsedDouble == null) {
      errors.add(ProductImportRowError(row: row, field: field, message: "'$value' is not a valid integer."));
      return null;
    }
    final parsed = parsedDouble.toInt();
    if (minValue != null && parsed < minValue) {
      errors.add(ProductImportRowError(row: row, field: field, message: "'$value' must be $minValue or greater."));
      return null;
    }
    return parsed;
  }
}
