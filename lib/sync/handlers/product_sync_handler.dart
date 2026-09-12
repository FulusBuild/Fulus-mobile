import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
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
    required ProductRepository productRepository,
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
  })  : _productRepository = productRepository,
        _db = db,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState;

  final ProductRepository _productRepository;
  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;

  @override
  Future<void> sync(SyncQueueItem item) async {
    switch (item.operation) {
      case 'create':
        await _syncCreate(item.entityLocalId, operationId: item.id);
      case 'update':
        await _syncUpdate(item.entityLocalId, operationId: item.id);
      default:
        throw StateError(
          'ProductSyncHandler does not support operation "${item.operation}".',
        );
    }
  }

  Future<void> _syncCreate(String localId, {String? operationId}) async {
    final row = await _requireProductRow(localId);
    final product = row.toDomain();
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || device == null || device.status != 'active') {
      throw StateError('Fulus cloud authorization is required for product sync.');
    }

    final stock = await (_db.select(_db.productStockLevels)
          ..where((s) => s.productLocalId.equals(localId)))
        .getSingleOrNull();
    final payload = <String, dynamic>{
      'local_id': localId,
      'name': product.name,
      'sku': product.sku,
      'barcode': product.barcode,
      'category_id': product.categoryId,
      'supplier_id': product.supplierId,
      'cost_price': product.costPrice,
      'selling_price': product.sellingPrice,
      'low_stock_threshold': product.lowStockThreshold,
      'is_active': product.isActive,
      'initial_stock': stock?.currentStock ?? 0,
    };
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'product.create',
      operationId: operationId ?? localId,
      deviceClientId: device.deviceClientId,
      payload: payload,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final serverId = data['entity_id'] as String?;
    if (serverId == null) {
      throw StateError('Fulus product create returned no server entity ID.');
    }
    await _productRepository.markSynced(localId: localId, serverId: serverId);
  }

  Future<void> _syncUpdate(String localId, {String? operationId}) async {
    final row = await _requireProductRow(localId);
    final product = row.toDomain();
    final serverId = product.serverId;
    if (serverId == null) {
      throw StateError(
        'Cannot sync a product update before its create has synced '
        '(no serverId yet for $localId).',
      );
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || device == null || device.status != 'active') {
      throw StateError('Fulus cloud authorization is required for product sync.');
    }

    final payload = <String, dynamic>{
      'server_id': serverId,
      ...product.toUpdateDto().toJson(),
    };
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'product.update',
      operationId: operationId ?? localId,
      deviceClientId: device.deviceClientId,
      payload: payload,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final returnedId = data['entity_id'] as String?;
    if (returnedId != serverId) {
      throw StateError('Fulus product update returned an unexpected entity ID.');
    }
    await _productRepository.markSynced(localId: localId, serverId: serverId);
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
