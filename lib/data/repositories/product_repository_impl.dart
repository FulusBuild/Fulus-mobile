import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../sync/sync_queue.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../remote/endpoints/products_api.dart';
import 'product_mapper.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({
    required AppDatabase db,
    required ProductsApi productsApi,
    required SyncQueue syncQueue,
  })  : _db = db,
        _productsApi = productsApi,
        _syncQueue = syncQueue;

  final AppDatabase _db;
  final ProductsApi _productsApi;
  final SyncQueue _syncQueue;

  ProductWithStock _mapRow(TypedResult row) {
    final product = row.readTable(_db.products);
    // Nullable: a left-outer-joined row that simply hasn't been
    // reconciled yet (see syncFromServer's own comment on when that can
    // happen). Treated as zero, matching ProductStockLevels.currentStock's
    // own column default — "not yet known" and "known to be zero" are
    // deliberately not distinguished here, same as that column doesn't
    // distinguish them either.
    final stockLevel = row.readTableOrNull(_db.productStockLevels);
    return ProductWithStock(
      product: product.toDomain(),
      currentStock: stockLevel?.currentStock ?? 0,
    );
  }

  @override
  Stream<List<ProductWithStock>> watchProducts({required String locationId}) {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.deletedAt.isNull())
      // A POS product grid (Volume 4) shouldn't offer a discontinued
      // item — getProductById below deliberately does NOT apply this
      // same filter, since a direct lookup by an already-known id (e.g.
      // from a past sale or stock movement) should still resolve even
      // if the product was deactivated since.
      ..where(_db.products.isActive.equals(true));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductById(
    String localId, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.localId.equals(localId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId}) {
    // Inner join, not left-outer like the two methods above: a product
    // with no ProductStockLevels row yet has unknown stock, not zero
    // stock, and "unknown" shouldn't surface as a low-stock alert —
    // excluding it via inner join is a clearer way to say that than a
    // left join whose comparison would just always fail on a NULL
    // currentStock anyway.
    final query = _db.select(_db.products).join([
      innerJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.deletedAt.isNull())
      ..where(_db.products.isActive.equals(true))
      // Decision 18: "A product with tracking off never appears in Low
      // Stock or stock reports" — added alongside the column itself
      // (tables.dart's Products.tracksStock doc comment); this predicate
      // didn't exist before that column did.
      ..where(_db.products.tracksStock.equals(true))
      ..where(_db.productStockLevels.currentStock.isSmallerOrEqual(_db.products.lowStockThreshold));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
  }

  @override
  Future<ProductWithStock?> getProductByBarcode(
    String barcode, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.barcode.equals(barcode) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<ProductWithStock?> getProductBySku(
    String sku, {
    required String locationId,
  }) async {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.productStockLevels,
        _db.productStockLevels.productLocalId.equalsExp(_db.products.localId) &
            _db.productStockLevels.locationLocalId.equals(locationId),
      ),
    ])
      ..where(_db.products.sku.equals(sku) & _db.products.deletedAt.isNull());
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRow(row);
  }

  @override
  Future<Set<String>> getAllSkus() async {
    final rows = await (_db.selectOnly(_db.products)
          ..addColumns([_db.products.sku])
          ..where(_db.products.deletedAt.isNull()))
        .get();
    return rows.map((r) => r.read(_db.products.sku)!).toSet();
  }

  @override
  Future<Set<String>> getAllBarcodes() async {
    final rows = await (_db.selectOnly(_db.products)
          ..addColumns([_db.products.barcode])
          ..where(_db.products.deletedAt.isNull() & _db.products.barcode.isNotNull()))
        .get();
    return rows.map((r) => r.read(_db.products.barcode)!).toSet();
  }

  @override
  Future<void> syncFromServer() async {
    // Single location for this phase — Locations table's own comment:
    // "a single-location business has exactly one row here, created
    // silently at onboarding, no location UI ever surfacing." This
    // repository doesn't create that row itself (LocationRepositoryImpl
    // owns that, and doesn't exist yet either — handoff doc Section 4,
    // item 2). If none exists yet, the catalog still syncs in full
    // (Products has no location dependency at all — only
    // ProductStockLevels does), but stock-level reconciliation has
    // nowhere to key to and is skipped for this pass. A real, temporary
    // gap tied to Location not existing yet, flagged here rather than
    // worked around — not a bug in this method, and not something this
    // method should fix by creating a Location row itself, which isn't
    // its job.
    final location = await _db.select(_db.locations).getSingleOrNull();

    var page = 1;
    var totalPages = 1;
    do {
      final response = await _productsApi.listProducts(page: page);
      totalPages = response.totalPages;

      for (final item in response.items) {
        // insertOnConflictUpdate, not InsertMode.insertOrReplace:
        // Products has real dependents (StockMovements.productLocalId,
        // ProductStockLevels.productLocalId both reference it) and
        // SQLite's INSERT OR REPLACE deletes-then-reinserts on conflict,
        // which risks disturbing those references during something as
        // routine as a re-sync. A true UPSERT (update in place) doesn't
        // have that problem.
        await _db.into(_db.products).insertOnConflictUpdate(item.toDriftCompanion());
        if (location != null) {
          await _db.into(_db.productStockLevels).insertOnConflictUpdate(
                item.toStockLevelCompanion(locationLocalId: location.localId),
              );
        }
      }

      page++;
    } while (page <= totalPages);
  }

  @override
  Future<void> reconcileStockLevel({
    required String productLocalId,
    required String locationId,
    required int currentStock,
  }) async {
    final product = await (_db.select(_db.products)
          ..where((p) => p.localId.equals(productLocalId)))
        .getSingleOrNull();
    if (product == null) {
      // Shouldn't be reachable in practice: a StockMovement can only
      // reference a productLocalId that already exists locally (real FK
      // constraint — StockMovements.productLocalId references
      // Products), and every local Products row only ever comes from a
      // real server-side product via syncFromServer's own upsert. Kept
      // as a loud failure rather than a silent no-op in case that
      // invariant is ever violated by something calling this method
      // directly rather than through the normal StockMovementSyncHandler
      // path.
      throw StateError(
        'reconcileStockLevel called for product $productLocalId, which '
        'this device has no local Products row for.',
      );
    }

    await _db.into(_db.productStockLevels).insertOnConflictUpdate(
          ProductStockLevelsCompanion.insert(
            productLocalId: productLocalId,
            locationLocalId: locationId,
            currentStock: Value(currentStock),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  @override
  Future<Product> createProduct(ProductDraft draft) async {
    // Defense-in-depth fix (business-logic audit): AddEditProductScreen
    // already checks `price <= 0` before calling this (see that
    // screen's own `_save`), so sellingPrice wasn't directly reachable
    // through the normal UI — but nothing at this layer caught it
    // either. costPrice had no guard anywhere, UI or repository — a
    // negative cost here flows straight into every COGS calculation
    // this app has (costPriceAtSale is captured from this exact field
    // at cart-add time). 0 is allowed for costPrice — the same "cost
    // not yet known" state Quick Sale items and costDataCompleteness
    // already treat as legitimate, not an error — but sellingPrice
    // must be strictly positive; a product genuinely cannot be sold
    // for ₦0 or less.
    if (draft.sellingPrice <= 0) {
      throw ArgumentError.value(draft.sellingPrice, 'sellingPrice', 'must be > 0');
    }
    if (draft.costPrice < 0) {
      throw ArgumentError.value(draft.costPrice, 'costPrice', 'must be >= 0');
    }
    final existingSku = await (_db.select(_db.products)..where((p) => p.sku.equals(draft.sku) & p.deletedAt.isNull())).getSingleOrNull();
    if (existingSku != null) throw ArgumentError.value(draft.sku, 'sku', 'already exists');
    if (draft.barcode != null && draft.barcode!.isNotEmpty) {
      final existingBarcode = await (_db.select(_db.products)..where((p) => p.barcode.equals(draft.barcode!) & p.deletedAt.isNull())).getSingleOrNull();
      if (existingBarcode != null) throw ArgumentError.value(draft.barcode, 'barcode', 'already exists');
    }
    final localId = Ulid().toString();
    final product = draft.toProductEntity(localId: localId);

    await _db.transaction(() async {
      await _db.into(_db.products).insert(product.toDriftCompanion());

    // Always seeded, even when initialStock is 0 — a deliberate zero
    // (this product has none yet) is a different, more useful fact than
    // no row at all (nobody has ever recorded a count), and this is
    // exactly the seam SaleRepositoryImpl._decrementLocalStock's own
    // comment named as undone work. Reuses reconcileStockLevel rather
    // than duplicating its insertOnConflictUpdate — the product row
    // above already exists by the time this runs, so its not-found
    // guard can't fire here.
    await reconcileStockLevel(
      productLocalId: localId,
      locationId: draft.locationId,
      currentStock: draft.initialStock,
    );

      await _syncQueue.enqueue(SyncTask.createProduct(localId));
    });

    return product;
  }

  @override
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
  }) async {
    // Defense-in-depth fix (business-logic audit): same reasoning as
    // createProduct's own guard above — only fires when the field is
    // actually being changed here, matching this method's existing
    // partial-update convention (Value.absent() for anything not
    // passed).
    if (sellingPrice != null && sellingPrice <= 0) {
      throw ArgumentError.value(sellingPrice, 'sellingPrice', 'must be > 0');
    }
    if (costPrice != null && costPrice < 0) {
      throw ArgumentError.value(costPrice, 'costPrice', 'must be >= 0');
    }
    final current = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (current == null) throw StateError('Product $localId does not exist.');
    if (sku != null) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.sku.equals(sku) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(sku, 'sku', 'already exists');
    }
    if (barcode != null && barcode.isNotEmpty) {
      final duplicate = await (_db.select(_db.products)..where((p) => p.barcode.equals(barcode) & p.localId.equals(localId).not() & p.deletedAt.isNull())).getSingleOrNull();
      if (duplicate != null) throw ArgumentError.value(barcode, 'barcode', 'already exists');
    }
    // Value.absent() for anything not passed — a genuine partial
    // update, not a reset, same convention as setLocalOverrides below
    // and as the backend's own PATCH (exclude_unset=True, verified
    // directly against inventory_service.update_product).
    await (_db.update(_db.products)..where((p) => p.localId.equals(localId)))
        .write(
      ProductsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        sku: sku == null ? const Value.absent() : Value(sku),
        barcode: barcode == null ? const Value.absent() : Value(barcode),
        categoryId: categoryId == null ? const Value.absent() : Value(categoryId),
        supplierId: supplierId == null ? const Value.absent() : Value(supplierId),
        costPrice: costPrice == null ? const Value.absent() : Value(costPrice),
        sellingPrice: sellingPrice == null ? const Value.absent() : Value(sellingPrice),
        lowStockThreshold: lowStockThreshold == null ? const Value.absent() : Value(lowStockThreshold),
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        syncStatus: Value(SyncStatus.pending),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Collapse repeated edits into the same durable queue item. The
    // handler reads the current persisted row at drain time, so one
    // queued update is sufficient even if several edits happened while
    // offline. This also prevents an edit storm from producing redundant
    // server operations.
    await _syncQueue.enqueue(SyncTask.updateProduct(localId));
  }

  @override
  Future<void> archiveProduct(String localId) async {
    final now = DateTime.now();
    final row = await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (row == null) throw StateError('Product $localId does not exist.');
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.localId.equals(localId))).write(
        ProductsCompanion(
          deletedAt: Value(now),
          isActive: const Value(false),
          updatedAt: Value(now),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      await _syncQueue.enqueue(SyncTask.updateProduct(localId));
    });
  }

  @override
  Future<void> markSynced({required String localId, required String serverId}) async {
    await (_db.update(_db.products)..where((p) => p.localId.equals(localId)))
        .write(
      ProductsCompanion(
        serverId: Value(serverId),
        syncStatus: Value(SyncStatus.settled),
      ),
    );
  }

  @override
  Future<void> setLocalOverrides({
    required String productLocalId,
    bool? tracksStock,
    String? unit,
    String? photoPath,
  }) async {
    // Every field Value.absent() unless explicitly passed — a partial
    // update, not a reset. updatedAt IS always touched, same "this row
    // changed" signal every other write method in this codebase gives,
    // even though this particular change has nothing to sync.
    await (_db.update(_db.products)
          ..where((p) => p.localId.equals(productLocalId)))
        .write(
      ProductsCompanion(
        tracksStock: tracksStock == null ? const Value.absent() : Value(tracksStock),
        unit: unit == null ? const Value.absent() : Value(unit),
        photoPath: photoPath == null ? const Value.absent() : Value(photoPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
