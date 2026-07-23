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
}
