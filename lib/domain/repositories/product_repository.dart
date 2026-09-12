import '../entities/product.dart';

/// Architecture Section 4's repository pattern, applied to Products.
/// **Phase 0 completion pass**: no longer read-only — Product Design
/// Bible Volume 6's "Adding & Managing Products" is a genuine mobile
/// capability, not a desktop-only one (confirmed directly against the
/// Bible's own text), so [createProduct]/[updateProduct] now exist
/// alongside the read/pull-sync methods below. Local-write-first,
/// enqueue-and-return, same shape as CategoryRepository/
/// SupplierRepository — see those interfaces' own doc comments for the
/// general reasoning.
abstract class ProductRepository {
  /// Reactive by default — a POS product grid (Volume 4) needs to
  /// reflect a stock change (this device's own sale, or a synced-down
  /// change from another device) immediately.
  Stream<List<ProductWithStock>> watchProducts({required String locationId});

  Future<ProductWithStock?> getProductById(
    String localId, {
    required String locationId,
  });

  /// Local-only lookup — a barcode scan at checkout (Volume 5) needs an
  /// instant answer, not a network round-trip; this is exactly why the
  /// device is carrying a full local copy of the catalog in the first
  /// place. Mirrors backend GET /products/by-barcode/{barcode}'s
  /// *purpose* (find the one matching product), not its transport —
  /// there is deliberately no remote equivalent call on ProductsApi for
  /// this, unlike every other method here.
  Future<ProductWithStock?> getProductByBarcode(
    String barcode, {
    required String locationId,
  });

  /// Same reasoning as [getProductByBarcode] — local-only, for the same
  /// reason.
  Future<ProductWithStock?> getProductBySku(
    String sku, {
    required String locationId,
  });

  /// Volume 6's low-stock alerts — a distinct query rather than a
  /// client-side filter over [watchProducts], so the (not yet built)
  /// concrete implementation can push the threshold comparison into the
  /// SQL query itself rather than fetching every product to filter in
  /// Dart.
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId});

  /// Every non-deleted product's SKU, for uniqueness checks that need
  /// to compare against the *whole* catalog rather than one product at
  /// a time — ImportProductsFromCsv's main use, chosen over checking
  /// one-by-one for the same N+1-avoidance reason
  /// import_service.py's own pre-loaded `existing_skus` set exists.
  Future<Set<String>> getAllSkus();

  /// Same contract as [getAllSkus], for barcodes — null/empty barcodes
  /// excluded, since a product with no barcode shouldn't collide with
  /// another product that also has none.
  Future<Set<String>> getAllBarcodes();

  /// Adds a new product to the catalog — Volume 6's "Add Product," name
  /// and price required, everything else optional (see [ProductDraft]'s
  /// own doc comment). Local-write-first: returns as soon as the local
  /// Products row (and, if [ProductDraft.initialStock] is nonzero, the
  /// matching ProductStockLevels row) is written and a sync task is
  /// queued — never awaits the network.
  Future<Product> createProduct(ProductDraft draft);

  /// Edits an existing product — every field optional, `null` meaning
  /// "leave this one alone" (same partial-update convention as
  /// [setLocalOverrides] below), matching the backend's own
  /// ProductUpdate/PATCH semantics exactly.
  Future<void> updateProduct({
    required String localId,
    String? name,
    String? sku,
    String? barcode,
    String? categoryId,
    String? supplierId,
    double? costPrice,
    double? sellingPrice,
    int? lowStockThreshold,
    bool? isActive,
  });

  /// Called by ProductSyncHandler once a locally-created or -edited
  /// product has reached the server — same role as every other
  /// repository's markSynced.
  Future<void> archiveProduct(String localId);

  Future<void> markSynced({required String localId, required String serverId});

  /// Pulls the current catalog and stock levels from the backend and
  /// reconciles them locally — see LocationRepository.syncFromServer's
  /// own comment on this being a pull, not a push.
  Future<void> syncFromServer();

  /// Reconciles ONE product's stock level from a current_stock value the
  /// caller already has fresh, without re-pulling the entire catalog to
  /// get it — closes the gap Section 4 (item 1 of the handoff doc)
  /// anticipated: every one of the three stock-movement write endpoints
  /// (stock-in/stock-out/adjust-stock) returns the product's own
  /// up-to-date current_stock in its response (ProductOut, not the
  /// movement record — see StockMovementsApi's own doc comment), and
  /// until this method existed there was nowhere on-device to send it.
  /// StockMovementSyncHandler and ProductSyncHandler (for a fresh
  /// product's own [ProductDraft.initialStock]) are today's callers.
  /// [productLocalId] must already exist in the local Products table —
  /// if it doesn't (meaning this device never actually pulled that
  /// product down via [syncFromServer]), this throws rather than
  /// silently inserting a stock-level row for a product this device
  /// doesn't otherwise know anything about.
  Future<void> reconcileStockLevel({
    required String productLocalId,
    required String locationId,
    required int currentStock,
  });

  /// The only write path for [Product.tracksStock]/[Product.unit]/
  /// [Product.photoPath] — see those fields' own doc comments for why
  /// they can't go through the normal server-authoritative path
  /// everything else on Product does. No sync task is enqueued: there is
  /// nowhere on the backend to push these three fields to today, so this
  /// is a genuinely local-only write, not an optimistic one waiting on a
  /// round trip. Only the fields actually passed are changed — a `null`
  /// argument means "leave this one alone," not "clear it," matching
  /// every other partial-update method in this codebase's own
  /// convention.
  Future<void> setLocalOverrides({
    required String productLocalId,
    bool? tracksStock,
    String? unit,
    String? photoPath,
  });
}
