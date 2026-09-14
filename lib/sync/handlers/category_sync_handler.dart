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
    if (item.operation != 'create') {
      throw StateError(
        'CategorySyncHandler does not support operation "${item.operation}" yet — only "create" is implemented.',
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
    if (businessId == null || device?.status != 'active') {
      throw StateError('Fulus cloud authorization is required for category sync.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'category.create',
      operationId: item.id,
      deviceClientId: device!.deviceClientId,
      payload: {
        'name': category.name,
        'description': category.description,
      },
    );
    final data = Map<String, dynamic>.from(result['data'] as Map);
    final serverId = data['entity_id'] as String?;
    if (serverId == null) {
      throw StateError('Fulus category sync returned no server entity ID.');
    }
    await _categoryRepository.markSynced(
      localId: category.localId,
      serverId: serverId,
    );
  }
}
