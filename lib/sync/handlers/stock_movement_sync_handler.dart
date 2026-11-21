import '../../data/local/database/database.dart';
import '../../core/errors/failure.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_movement_repository.dart';
import '../sync_handler.dart';

/// Pushes stock-in/out through Fulus Cloud. Sale movements are server-derived.
/// Absolute adjustments use the server's serialized absolute-target command.
class StockMovementSyncHandler implements SyncHandler {
  StockMovementSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required StockMovementRepository stockMovementRepository,
    required ProductRepository productRepository,
  }) : _db = db,
       _fulusSyncApi = fulusSyncApi,
       _fulusConnectionState = fulusConnectionState,
       _stockMovementRepository = stockMovementRepository,
       _productRepository = productRepository;

  final AppDatabase _db;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final StockMovementRepository _stockMovementRepository;
  final ProductRepository _productRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError('StockMovementSyncHandler supports only create.');
    }
    final movement = await _stockMovementRepository.getStockMovementById(
      item.entityLocalId,
    );
    if (movement == null)
      throw StateError(
        'No local stock movement found for ${item.entityLocalId}.',
      );
    if (movement.serverId?.isNotEmpty == true) return;
    if (movement.movementType == StockMovementType.sale) {
      throw StateError(
        'Sale stock movements are created by the server sale transaction.',
      );
    }
    if (movement.movementType == StockMovementType.transfer) {
      throw StateError(
        'Stock transfers are not supported by the Fulus Cloud command API yet.',
      );
    }
    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null ||
        businessId.isEmpty ||
        device == null ||
        device.status != 'active') {
      throw StateError(
        'Fulus Cloud device authorization is required for stock sync.',
      );
    }
    final deviceClientId = device.deviceClientId;
    final product =
        await (_db.select(_db.products)
              ..where((p) => p.localId.equals(movement.productLocalId)))
            .getSingleOrNull();
    final productId = product?.serverId;
    if (productId == null || productId.isEmpty)
      throw StateError('Stock movement product has no server identity yet.');
    final location = await (_db.select(
      _db.locations,
    )..where((l) => l.localId.equals(movement.locationId))).getSingleOrNull();
    final locationId = location?.serverId;
    if (locationId == null || locationId.isEmpty)
      throw StateError('Stock movement location has no server identity yet.');

    if (movement.movementType == StockMovementType.adjustment) {
      final newQuantity = movement.newQuantity;
      if (newQuantity == null || newQuantity < 0) {
        throw StateError(
          'Stock adjustment target quantity must be non-negative.',
        );
      }
      final result = await _submitStockOperation(
        item: item,
        businessId: businessId,
        deviceClientId: deviceClientId,
        productId: productId,
        locationServerId: locationId,
        productLocalId: movement.productLocalId,
        locationLocalId: movement.locationId,
        operationType: 'stock_adjustment.create',
        payload: {
          'business_id': businessId,
          'product_id': productId,
          'location_id': locationId,
          'new_quantity': newQuantity,
          'reason': movement.reason ?? 'Stock adjustment',
          'operation_id': item.id,
        },
      );
      final data = result['data'];
      if (data is! Map)
        throw StateError('Fulus stock adjustment returned no response data.');
      final currentStock = (data['current_stock'] as num?)?.toInt();
      if (currentStock != null) {
        await _productRepository.reconcileStockLevel(
          productLocalId: movement.productLocalId,
          locationId: movement.locationId,
          currentStock: currentStock,
          operationId: item.id,
        );
      }
      await _stockMovementRepository.markSettled(
        localId: movement.localId,
        operationId: item.id,
        serverId: (data['entity_id'] ?? data['movement_id'])?.toString(),
      );
      return;
    }

    final quantity = movement.quantity;
    if (quantity == null || quantity <= 0)
      throw StateError('Stock movement quantity must be positive.');
    final delta = movement.movementType == StockMovementType.stockIn
        ? quantity
        : -quantity;
    final result = await _submitStockOperation(
      item: item,
      businessId: businessId,
      deviceClientId: deviceClientId,
      productId: productId,
      locationServerId: locationId,
      productLocalId: movement.productLocalId,
      locationLocalId: movement.locationId,
      operationType: 'stock_movement.create',
      payload: {
        'business_id': businessId,
        'product_id': productId,
        'location_id': locationId,
        'quantity_delta': delta,
        'reason': movement.reason ?? 'Stock movement',
        'operation_id': item.id,
      },
    );
    final data = result['data'];
    if (data is! Map)
      throw StateError('Fulus stock sync returned no response data.');
    final currentStock = (data['current_stock'] as num?)?.toInt();
    if (currentStock != null) {
      await _productRepository.reconcileStockLevel(
        productLocalId: movement.productLocalId,
        locationId: movement.locationId,
        currentStock: currentStock,
        operationId: item.id,
      );
    }
    await _stockMovementRepository.markSettled(
      localId: movement.localId,
      operationId: item.id,
      serverId: (data['entity_id'] ?? data['movement_id'])?.toString(),
    );
  }

  Future<Map<String, dynamic>> _submitStockOperation({
    required SyncQueueItem item,
    required String businessId,
    required String deviceClientId,
    required String productId,
    required String locationServerId,
    required String productLocalId,
    required String locationLocalId,
    required String operationType,
    required Map<String, dynamic> payload,
  }) async {
    try {
      return await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: operationType,
        operationId: item.id,
        deviceClientId: deviceClientId,
        clientReference: item.entityLocalId,
        payload: payload,
      );
    } on BusinessRuleFailure {
      // The local projection already includes this optimistic operation. If
      // the authoritative command rejects it, fetch the canonical product
      // state and reset this location before the queue item is parked.
      // ProductRepository's operation-aware fence leaves any newer queued
      // mutation in control of the local projection.
      try {
        final canonical = await _fulusSyncApi.fetchCanonicalEntity(
          businessId: businessId,
          entityType: 'product',
          entityId: productId,
          deviceClientId: deviceClientId,
        );
        if (canonical.operation == 'upsert') {
          final rawLevels = canonical.data['stock_levels'];
          if (rawLevels is! List) {
            throw StateError('Canonical product response has no stock levels.');
          }
          final levels = rawLevels.whereType<Map>().map(
            (row) => Map<String, dynamic>.from(row),
          );
          final level = levels.firstWhere(
            (row) => row['location_id'] == locationServerId,
            orElse: () => const <String, dynamic>{},
          );
          final rawStock = level['current_stock'];
          final currentStock = rawStock == null
              ? 0
              : rawStock is num && rawStock == rawStock.toInt()
              ? rawStock.toInt()
              : throw StateError('Canonical stock quantity is invalid.');
          await _productRepository.reconcileStockLevel(
            productLocalId: productLocalId,
            locationId: locationLocalId,
            currentStock: currentStock,
            operationId: item.id,
          );
        }
      } catch (_) {
        // Preserve the original authoritative rejection. The sync item stays
        // attention-needed; a failed refresh must not turn a rejected stock
        // write into an automatic retry.
      }
      rethrow;
    }
  }
}
