import 'package:drift/drift.dart';

import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/products_api.dart';
import '../../data/repositories/product_mapper.dart';
import '../../domain/repositories/product_repository.dart';
import '../sync_handler.dart';

/// **Phase 0 completion pass.** Second handler in this codebase (after
/// CashDrawerShiftSyncHandler) that supports two operations for one
/// entity type — 'create' for a brand-new product (Product Design Bible
/// Volume 6, "Adding & Managing Products") and 'update' for an edit to
/// an existing one, both enqueued by ProductRepositoryImpl.
///
/// Needs the local Location row directly (not just ProductRepository),
/// for the same single-reason ProductRepositoryImpl.syncFromServer
/// already does: 'create' needs to read back the ProductStockLevels row
/// createProduct seeded at a specific location, and Phase 0 is
/// single-location, so there's exactly one to read — see that method's
/// own doc comment for the fuller reasoning, unchanged here.
class ProductSyncHandler implements SyncHandler {
  ProductSyncHandler({
    required ProductsApi productsApi,
    required ProductRepository productRepository,
    required AppDatabase db,
  })  : _productsApi = productsApi,
        _productRepository = productRepository,
        _db = db;

  final ProductsApi _productsApi;
  final ProductRepository _productRepository;
  final AppDatabase _db;

  @override
  Future<void> sync(SyncQueueItem item) async {
    switch (item.operation) {
      case 'create':
        await _syncCreate(item.entityLocalId);
      case 'update':
        await _syncUpdate(item.entityLocalId);
      default:
        throw StateError(
          'ProductSyncHandler does not support operation "${item.operation}".',
        );
    }
  }

  Future<void> _syncCreate(String localId) async {
    final row = await _requireProductRow(localId);
    final product = row.toDomain();
    final location = await _db.select(_db.locations).getSingleOrNull();
    var initialStock = 0;
    if (location != null) {
      final stockLevel = await (_db.select(_db.productStockLevels)
            ..where((s) =>
                s.productLocalId.equals(localId) & s.locationLocalId.equals(location.localId)))
          .getSingleOrNull();
      initialStock = stockLevel?.currentStock ?? 0;
    }

    final response = await _productsApi.createProduct(
      product.toCreateDto(initialStock: initialStock),
    );
    await _productRepository.markSynced(localId: localId, serverId: response.id);

    // Reconcile back, same reasoning StockMovementSyncHandler already
    // established: the server is the one source of truth for
    // current_stock once this create has actually landed.
    if (location != null) {
      await _productRepository.reconcileStockLevel(
        productLocalId: localId,
        locationId: location.localId,
        currentStock: response.currentStock,
      );
    }
  }

  Future<void> _syncUpdate(String localId) async {
    final row = await _requireProductRow(localId);
    final product = row.toDomain();
    if (product.serverId == null) {
      // Same ordering guarantee CashDrawerShiftSyncHandler's own
      // create-before-close comment describes: this product's own
      // 'create' task is always enqueued (and, under normal
      // priority-ordered draining, processed) before any 'update' for
      // it could be. Thrown rather than silently skipped so the sync
      // engine's normal retry/backoff handles the ordering edge case,
      // not this handler guessing at one.
      throw StateError(
        'Cannot sync a product update before its create has synced '
        '(no serverId yet for $localId).',
      );
    }

    final response = await _productsApi.updateProduct(
      productId: product.serverId!,
      dto: product.toUpdateDto(),
    );
    await _productRepository.markSynced(localId: localId, serverId: response.id);
  }

  Future<ProductRow> _requireProductRow(String localId) async {
    final row =
        await (_db.select(_db.products)..where((p) => p.localId.equals(localId))).getSingleOrNull();
    if (row == null) {
      throw StateError(
        'No local product found for $localId — the queue item outlived its own row.',
      );
    }
    return row;
  }
}
