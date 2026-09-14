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
    if (item.operation != 'create') {
      throw StateError(
        'SupplierSyncHandler does not support operation "${item.operation}" yet — only "create" is implemented.',
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
    if (businessId == null || device?.status != 'active') {
      throw StateError('Fulus cloud authorization is required for supplier sync.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'supplier.create',
      operationId: item.id,
      deviceClientId: device!.deviceClientId,
      payload: {
        'name': supplier.name,
        'phone': supplier.phone,
        'email': supplier.email,
        'address': supplier.address,
      },
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final serverId = data['entity_id'] as String?;
    if (serverId == null) {
      throw StateError('Fulus supplier sync returned no server entity ID.');
    }
    await _supplierRepository.markSynced(
      localId: supplier.localId,
      serverId: serverId,
    );
  }
}
