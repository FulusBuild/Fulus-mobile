import '../../core/utils/csv_parser.dart';
import '../entities/category.dart';
import '../entities/product.dart';
import '../entities/product_import.dart';
import '../entities/supplier.dart';
import '../repositories/category_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/supplier_repository.dart';
import 'product_import_engine.dart';

/// **Phase 0 completion pass.** Product Design Bible Volume 6, "Bulk
/// Import" (the CSV path). Architecture Section 1's own naming example
/// for this folder is "one class per meaningful action" —
/// `ImportProductsFromCsv` is exactly that shape, orchestrating three
/// repository *interfaces* (never a concrete Drift type — this file has
/// no data/ or Flutter import anywhere in it, same Business Engine
/// isolation every other usecase here holds itself to) plus the pure
/// [ProductImportEngine] and [CsvParser].
///
/// Deliberately does NOT talk to ProductsApi/CategoriesApi/SuppliersApi
/// directly, or wait on a sync round-trip for anything — every created
/// row goes through the exact same local-write-first
/// createProduct/createCategory/createSupplier calls a single manual
/// "Add Product" action would use, each already queuing its own sync
/// task the normal way. A 200-row import queues up to 200 sync tasks
/// exactly the way 200 individual manual adds would; there's nothing
/// import-specific for the sync layer to know about.
class ImportProductsFromCsv {
  const ImportProductsFromCsv({
    required ProductRepository productRepository,
    required CategoryRepository categoryRepository,
    required SupplierRepository supplierRepository,
    ProductImportEngine engine = const ProductImportEngine(),
    CsvParser csvParser = const CsvParser(),
  })  : _productRepository = productRepository,
        _categoryRepository = categoryRepository,
        _supplierRepository = supplierRepository,
        _engine = engine,
        _csvParser = csvParser;

  final ProductRepository _productRepository;
  final CategoryRepository _categoryRepository;
  final SupplierRepository _supplierRepository;
  final ProductImportEngine _engine;
  final CsvParser _csvParser;

  /// [locationId] is where every row's [ProductDraft.initialStock] gets
  /// seeded — same single-location assumption ProductRepositoryImpl and
  /// StockMovementSyncHandler already make elsewhere in this phase, not
  /// a new one introduced here.
  Future<ProductImportResult> call({
    required String csvContent,
    required String locationId,
  }) async {
    final parsed = _csvParser.parseWithHeaders(csvContent);

    final existingSkus = await _productRepository.getAllSkus();
    final existingBarcodes = await _productRepository.getAllBarcodes();

    final plan = _engine.validate(
      headers: parsed.headers,
      rows: parsed.rows,
      existingSkus: existingSkus,
      existingBarcodes: existingBarcodes,
    );

    if (plan.isRejected) {
      return ProductImportResult(
        successCount: 0,
        errorCount: plan.headerErrors.length,
        totalRows: 0,
        errors: plan.headerErrors,
        createdProductLocalIds: const [],
      );
    }

    // Pre-loaded once, mutated in place as new names get created during
    // the loop below — matches import_service.py's own cat_map/sup_map
    // preload-then-extend pattern, verified directly, for the same
    // N+1-avoidance reason.
    final categoryIdByLowerName = <String, String>{
      for (final c in await _categoryRepository.watchCategories().first) c.name.toLowerCase(): c.localId,
    };
    final supplierIdByLowerName = <String, String>{
      for (final s in await _supplierRepository.watchSuppliers().first) s.name.toLowerCase(): s.localId,
    };

    final errors = <ProductImportRowError>[...plan.rowErrors];
    final createdIds = <String>[];

    for (final row in plan.rowsToCreate) {
      try {
        String? categoryId;
        if (row.categoryName != null) {
          categoryId = await _resolveOrCreate(
            name: row.categoryName!,
            cache: categoryIdByLowerName,
            create: (name) => _categoryRepository.createCategory(CategoryDraft(name: name)).then((c) => c.localId),
          );
        }

        String? supplierId;
        if (row.supplierName != null) {
          supplierId = await _resolveOrCreate(
            name: row.supplierName!,
            cache: supplierIdByLowerName,
            create: (name) => _supplierRepository.createSupplier(SupplierDraft(name: name)).then((s) => s.localId),
          );
        }

        final product = await _productRepository.createProduct(ProductDraft(
          name: row.name,
          sku: row.sku,
          barcode: row.barcode,
          categoryId: categoryId,
          supplierId: supplierId,
          costPrice: row.costPrice,
          sellingPrice: row.sellingPrice,
          lowStockThreshold: row.lowStockThreshold,
          initialStock: row.initialStock,
          locationId: locationId,
        ));
        createdIds.add(product.localId);
      } catch (e) {
        // A validated row can still fail here for a reason validation
        // couldn't see in advance (e.g. this specific local database
        // rejecting the write) — recorded as a row error rather than
        // aborting the rest of the import, same "never stop on first
        // error" principle the validation pass itself follows.
        errors.add(ProductImportRowError(row: row.row, message: 'Could not save this row: $e'));
      }
    }

    return ProductImportResult(
      successCount: createdIds.length,
      errorCount: errors.length,
      totalRows: plan.totalRows,
      errors: errors,
      createdProductLocalIds: createdIds,
    );
  }

  Future<String> _resolveOrCreate({
    required String name,
    required Map<String, String> cache,
    required Future<String> Function(String name) create,
  }) async {
    final key = name.toLowerCase();
    final cached = cache[key];
    if (cached != null) return cached;
    final newId = await create(name);
    cache[key] = newId;
    return newId;
  }
}
