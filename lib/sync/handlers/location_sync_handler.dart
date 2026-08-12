import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/locations_api.dart';
import '../../domain/entities/location.dart';
import '../../domain/repositories/location_repository.dart';
import '../sync_handler.dart';

/// Pushes a mobile-created location to the backend — the create side of
/// Location's now-bidirectional sync (see `LocationRepository`'s own
/// doc comment). Structurally identical to SupplierSyncHandler /
/// CategorySyncHandler: only "create" exists because nothing in this
/// codebase yet edits or deletes a location from mobile, matching
/// exactly what those two handlers support today too.
class LocationSyncHandler implements SyncHandler {
  LocationSyncHandler({
    required LocationsApi locationsApi,
    required LocationRepository locationRepository,
  })  : _locationsApi = locationsApi,
        _locationRepository = locationRepository;

  final LocationsApi _locationsApi;
  final LocationRepository _locationRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      throw StateError(
        'LocationSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final location = await _locationRepository.getLocationById(item.entityLocalId);
    if (location == null) {
      throw StateError(
        'No local location found for ${item.entityLocalId} — the queue '
        'item outlived its own row.',
      );
    }

    final response = await _locationsApi.createLocation(
      LocationCreateDto(name: location.name),
    );

    await _locationRepository.markSynced(
      localId: location.localId,
      serverId: response.serverId!,
    );
  }
}
