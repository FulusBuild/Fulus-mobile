import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../sync_handler.dart';

class SupplierSyncHandler implements SyncHandler {
  SupplierSyncHandler({
    required SupplierRepository supplierRepository,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
  })  : _supplierRepository = supplierRepository,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState;

  final SupplierRepository _supplierRepository;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create' && item.operation != 'update') {
      throw StateError(
        'SupplierSyncHandler does not support operation "${item.operation}".',
      );
    }

    final supplier = await _supplierRepository.getSupplierById(item.entityLocalId);
    if (supplier == null) {
      throw StateError(
        'No local supplier found for ${item.entityLocalId} — the queue item outlived its own row.',
      );
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || device == null || device.status != 'active') {
      throw StateError('Fulus cloud authorization is required for supplier sync.');
    }

    final isDelete = supplier.deletedAt != null;
    if (isDelete && supplier.serverId == null && item.operation == 'update') {
      throw StateError(
        'Cannot sync supplier deletion before its create has synced.',
      );
    }

    final operationId = item.id;
    // A queued create may be archived before first cloud delivery. Create
    // the authoritative row first; only a row with a server identity can
    // use supplier.delete.
    final operationType = (isDelete && supplier.serverId != null)
        ? 'supplier.delete'
        : 'supplier.${item.operation}';
    final payload = <String, dynamic>{
      'name': supplier.name,
      'phone': supplier.phone,
      'email': supplier.email,
      'address': supplier.address,
      if (supplier.serverId != null) 'server_id': supplier.serverId,
      if (item.baseCursor != null) 'base_cursor': item.baseCursor,
    };

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: operationType,
      operationId: operationId,
      deviceClientId: device.deviceClientId,
      payload: isDelete
          ? {
              'server_id': supplier.serverId,
              if (item.baseCursor != null) 'base_cursor': item.baseCursor,
            }
          : payload,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final serverId = (data['entity_id'] as String?) ?? supplier.serverId;
    if (serverId == null) {
      throw StateError('Fulus supplier sync returned no server entity ID.');
    }

    if (isDelete && item.operation == 'create' && supplier.serverId == null) {
      final deleteResult = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'supplier.delete',
        operationId: '${operationId}:delete',
        deviceClientId: device.deviceClientId,
        payload: {'server_id': serverId},
      );
      final deleteData = Map<String, dynamic>.from(deleteResult['data'] as Map);
      if ((deleteData['entity_id'] as String?) != serverId) {
        throw StateError('Fulus supplier delete returned an unexpected entity ID.');
      }
    }

    await _supplierRepository.markSynced(
      localId: supplier.localId,
      serverId: serverId,
    );
  }
}
