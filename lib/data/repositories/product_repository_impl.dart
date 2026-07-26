import 'package:drift/drift.dart';

import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../remote/endpoints/products_api.dart';
import 'product_mapper.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({
    required AppDatabase db,
    required ProductsApi productsApi,
  })  : _db = db,
        _productsApi = productsApi;

  final AppDatabase _db;
  final ProductsApi _productsApi;

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
      ..where(_db.productStockLevels.currentStock.isSmallerOrEqual(_db.products.lowStockThreshold));
    return query.watch().map((rows) => rows.map(_mapRow).toList());
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
}
