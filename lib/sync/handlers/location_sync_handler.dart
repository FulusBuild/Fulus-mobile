import '../../data/local/database/database.dart';
import '../../data/remote/fulus_connection_state.dart';
import '../../data/remote/fulus_sync_api.dart';
import '../../domain/repositories/location_repository.dart';
import '../sync_handler.dart';

/// Pushes mobile-created locations through the authoritative Fulus Cloud API.
class LocationSyncHandler implements SyncHandler {
  LocationSyncHandler({
    required AppDatabase db,
    required FulusSyncApi fulusSyncApi,
    required FulusConnectionState fulusConnectionState,
    required LocationRepository locationRepository,
  })  : _fulusSyncApi = fulusSyncApi,
        _fulusConnectionState = fulusConnectionState,
        _locationRepository = locationRepository;

  final FulusSyncApi _fulusSyncApi;
  final FulusConnectionState _fulusConnectionState;
  final LocationRepository _locationRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'LocationSyncHandler does not support operation "${item.operation}" yet — only "create" is implemented.',
      );
    }

    final location = await _locationRepository.getLocationById(item.entityLocalId);
    if (location == null) {
      throw StateError('No local location found for ${item.entityLocalId}.');
    }
    if (location.serverId?.isNotEmpty == true) return;

    final businessId = _fulusConnectionState.selectedBusinessId;
    final device = _fulusConnectionState.registeredDevice;
    if (businessId == null || businessId.isEmpty || device?.status != 'active') {
      throw StateError('Fulus Cloud device authorization is required for location sync.');
    }

    final result = await _fulusSyncApi.submitOperation(
      businessId: businessId,
      operationType: 'location.create',
      operationId: item.id,
      clientReference: location.localId,
      deviceClientId: device!.deviceClientId,
      payload: {
        'business_id': businessId,
        'operation_id': item.id,
        'client_reference': location.localId,
        'name': location.name,
      },
    );

    final data = result['data'];
    if (data is! Map) {
      throw StateError('Fulus location sync returned no response data.');
    }
    final serverId = (data['entity_id'] ?? data['location_id'] ?? data['id'])?.toString();
    if (serverId == null || serverId.isEmpty) {
      throw StateError('Fulus location sync returned no server entity ID.');
    }
    await _locationRepository.markSynced(
      localId: location.localId,
      serverId: serverId,
    operationId: item.id,
    );
  }
}
