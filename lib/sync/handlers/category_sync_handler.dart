import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/category_repository.dart';
import '../sync_handler.dart';

class CategorySyncHandler implements SyncHandler {
  CategorySyncHandler({
    required CategoryRepository categoryRepository,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
  })  : _categoryRepository = categoryRepository,
        _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState;

  final CategoryRepository _categoryRepository;
  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create' && item.operation != 'update') {
      throw StateError(
        'CategorySyncHandler does not support operation "${item.operation}".',
      );
    }

    final category = await _categoryRepository.getCategoryById(item.entityLocalId);
    if (category == null) {
      throw StateError(
        'No local category found for ${item.entityLocalId} — the queue item outlived its own row.',
      );
    }

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || device == null || device.status != 'active') {
      throw StateError('Fulus cloud authorization is required for category sync.');
    }

    final isDelete = category.deletedAt != null;
    if (isDelete && category.serverId == null && item.operation == 'update') {
      throw StateError(
        'Cannot sync category deletion before its create has synced.',
      );
    }

    final operationId = item.id;
    // A queued create may be archived before first cloud delivery. Create
    // the authoritative row first; only a row with a server identity can
    // use category.delete.
    final operationType = (isDelete && category.serverId != null)
        ? 'category.delete'
        : 'category.${item.operation}';
    final createOrUpdatePayload = <String, dynamic>{
      'name': category.name,
      'description': category.description,
      if (category.serverId != null) 'server_id': category.serverId,
      if (item.baseCursor != null) 'base_cursor': item.baseCursor,
    };

    final deletePayload = <String, dynamic>{
      'server_id': category.serverId,
      if (item.baseCursor != null) 'base_cursor': item.baseCursor,
    };

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: operationType,
      operationId: operationId,
      deviceClientId: device.deviceClientId,
      payload: operationType == 'category.delete' ? deletePayload : createOrUpdatePayload,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final createSequence = (data['sync_sequence'] as num?)?.toInt();
    final serverId = (data['entity_id'] as String?) ?? category.serverId;
    if (serverId == null) {
      throw StateError('Fulus category sync returned no server entity ID.');
    }

    if (isDelete && item.operation == 'create' && category.serverId == null) {
      final deleteResult = await _fulusSyncApi.submitOperation(
        businessId: businessId,
        operationType: 'category.delete',
        operationId: '${operationId}:delete',
        deviceClientId: device.deviceClientId,
        payload: {
          'server_id': serverId,
          if (createSequence != null) 'base_cursor': createSequence,
        },
      );
      final deleteData = Map<String, dynamic>.from(deleteResult['data'] as Map);
      if ((deleteData['entity_id'] as String?) != serverId) {
        throw StateError('Fulus category delete returned an unexpected entity ID.');
      }
    }

    await _categoryRepository.markSynced(
      localId: category.localId,
      serverId: serverId,
    operationId: item.id,
    );
  }
}
