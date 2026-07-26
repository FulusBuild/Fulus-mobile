import '../entities/product.dart';

/// Architecture Section 4's repository pattern, applied to Products.
/// Read + pull-sync only, same reasoning as LocationRepository: the
/// product catalog is business-wide and (per the same gap
/// SaleSyncHandler already documents — no product creation flow exists
/// on mobile yet) not something this phase creates from a device. What
/// mobile needs is to READ the catalog, joined with stock at whichever
/// location it cares about, and to know when it's running low.
abstract class ProductRepository {
  /// Reactive by default — a POS product grid (Volume 4) needs to
  /// reflect a stock change (this device's own sale, or a synced-down
  /// change from another device) immediately.
  Stream<List<ProductWithStock>> watchProducts({required String locationId});

  Future<ProductWithStock?> getProductById(
    String localId, {
    required String locationId,
  });

  /// Volume 6's low-stock alerts — a distinct query rather than a
  /// client-side filter over [watchProducts], so the (not yet built)
  /// concrete implementation can push the threshold comparison into the
  /// SQL query itself rather than fetching every product to filter in
  /// Dart.
  Stream<List<ProductWithStock>> watchLowStockProducts({required String locationId});

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
  /// StockMovementSyncHandler is the only caller today. [productLocalId]
  /// must already exist in the local Products table — if it doesn't
  /// (meaning this device never actually pulled that product down via
  /// [syncFromServer]), this throws rather than silently inserting a
  /// stock-level row for a product this device doesn't otherwise know
  /// anything about.
  Future<void> reconcileStockLevel({
    required String productLocalId,
    required String locationId,
    required int currentStock,
  });
}
