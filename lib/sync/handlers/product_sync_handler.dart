import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../data/repositories/product_mapper.dart';
import '../../domain/repositories/product_repository.dart';
import '../sync_handler.dart';

/// Pushes product catalog changes through the authoritative Fulus Cloud API.
///
/// Product category/supplier references may be local IDs for offline-created
/// rows or server IDs for rows reconciled from the cloud. The cloud API expects
/// server UUIDs, so resolve either representation before a product write.
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
        await _syncCreate(item.entityLocalId, operationId: item.id, baseCursor: item.baseCursor);
      case 'update':
        await _syncUpdate(item.entityLocalId, operationId: item.id, baseCursor: item.baseCursor);
      default:
        throw StateError(
          'ProductSyncHandler does not support operation "${item.operation}".',
        );
    }
  }

  Future<void> _syncCreate(String localId, {String? operationId, int? baseCursor}) async {
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
    final categoryId = await _resolveCatalogServerId(
      localId: product.categoryId,
      entityType: 'category',
    );
    final supplierId = await _resolveCatalogServerId(
      localId: product.supplierId,
      entityType: 'supplier',
    );
    final payload = <String, dynamic>{
      'local_id': localId,
      'name': product.name,
      'sku': product.sku,
      'barcode': product.barcode,
      'category_id': categoryId,
      'supplier_id': supplierId,
      'cost_price': product.costPrice,
      'selling_price': product.sellingPrice,
      'low_stock_threshold': product.lowStockThreshold,
      'is_active': product.isActive,
      'initial_stock': stock?.currentStock ?? 0,
      // The server must seed this exact location atomically with product creation.
      // Without it, a product created offline/local-first is created in Cloud with
      // stock 0 and the next pull legitimately overwrites the local quantity.
      'location_id': stock == null ? null : (await _resolveLocationServerId(productLocalId: localId, locationLocalId: stock.locationLocalId)),
    };
    final createOperationId = operationId ?? localId;
    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'product.create',
      operationId: createOperationId,
      deviceClientId: device.deviceClientId,
      payload: payload,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final serverId = data['entity_id'] as String?;
    if (serverId == null) {
      throw StateError('Fulus product create returned no server entity ID.');
    }

    if (product.deletedAt != null) {
      final deleteResult = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'product.delete',
        operationId: '${createOperationId}:delete',
        deviceClientId: device.deviceClientId,
        payload: {
          'server_id': serverId,
        },
      );
      final deleteData = Map<String, dynamic>.from(deleteResult['data'] as Map);
      if ((deleteData['entity_id'] as String?) != serverId) {
        throw StateError('Fulus product delete returned an unexpected entity ID.');
      }
    }

    await _productRepository.markSynced(localId: localId, serverId: serverId);
  }

  Future<void> _syncUpdate(String localId, {String? operationId, int? baseCursor}) async {
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

    if (product.deletedAt != null) {
      final result = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'product.delete',
        operationId: operationId ?? localId,
        deviceClientId: device.deviceClientId,
        payload: {
          'server_id': serverId,
          if (baseCursor != null) 'base_cursor': baseCursor,
        },
      );
      final data = Map<String, dynamic>.from(result['data'] as Map);
      if ((data['entity_id'] as String?) != serverId) {
        throw StateError('Fulus product delete returned an unexpected entity ID.');
      }
      await _productRepository.markSynced(localId: localId, serverId: serverId);
      return;
    }

    final categoryId = await _resolveCatalogServerId(
      localId: product.categoryId,
      entityType: 'category',
    );
    final supplierId = await _resolveCatalogServerId(
      localId: product.supplierId,
      entityType: 'supplier',
    );
    final payload = <String, dynamic>{
      'server_id': serverId,
      ...product.toUpdateDto().toJson(),
      'category_id': categoryId,
      'supplier_id': supplierId,
      if (baseCursor != null) 'base_cursor': baseCursor,
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

  Future<String?> _resolveCatalogServerId({
    required String? localId,
    required String entityType,
  }) async {
    if (localId == null || localId.isEmpty) return null;

    final serverId = switch (entityType) {
      'category' => await _resolveCategoryServerId(localId),
      'supplier' => await _resolveSupplierServerId(localId),
      _ => throw StateError('Unsupported product catalog dependency: $entityType'),
    };
    if (serverId == null || serverId.isEmpty) {
      throw StateError(
        'Product $entityType $localId has no server identity yet.',
      );
    }
    return serverId;
  }

  Future<String?> _resolveLocationServerId({required String productLocalId, required String locationLocalId}) async {
    final localRow = await (_db.select(_db.locations)
          ..where((l) => l.localId.equals(locationLocalId)))
        .getSingleOrNull();
    if (localRow?.serverId?.isNotEmpty == true) return localRow!.serverId;
    if (localRow != null) return null;
    final serverRow = await (_db.select(_db.locations)
          ..where((l) => l.serverId.equals(locationLocalId)))
        .getSingleOrNull();
    return serverRow?.serverId;
  }

  Future<String?> _resolveCategoryServerId(String localId) async {
    final localRow = await (_db.select(_db.categories)
          ..where((c) => c.localId.equals(localId)))
        .getSingleOrNull();
    if (localRow?.serverId?.isNotEmpty == true) return localRow!.serverId;
    if (localRow != null) return null;
    final serverRow = await (_db.select(_db.categories)
          ..where((c) => c.serverId.equals(localId)))
        .getSingleOrNull();
    return serverRow?.serverId;
  }

  Future<String?> _resolveSupplierServerId(String localId) async {
    final localRow = await (_db.select(_db.suppliers)
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    if (localRow?.serverId?.isNotEmpty == true) return localRow!.serverId;
    if (localRow != null) return null;
    final serverRow = await (_db.select(_db.suppliers)
          ..where((s) => s.serverId.equals(localId)))
        .getSingleOrNull();
    return serverRow?.serverId;
  }

  Future<ProductRow> _requireProductRow(String localId) async {
    final row = await (_db.select(_db.products)
          ..where((p) => p.localId.equals(localId)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'No local product found for $localId — the queue item outlived its own row.',
      );
    }
    return row;
  }
}
