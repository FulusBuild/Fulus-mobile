import 'package:drift/drift.dart';

import '../../domain/entities/location.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension LocationRowToDomain on LocationRow {
  Location toDomain() {
    return Location(
      localId: localId,
      serverId: serverId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}

extension LocationToCompanion on Location {
  /// A freshly created *local* location (see
  /// `LocationRepositoryImpl.createLocation`) — `pending`, not
  /// `settled`: unlike the old read-only assumption
  /// [LocationResponseDtoToCompanion] was built under, this row
  /// genuinely has a real sync task ahead of it now
  /// (`SyncTask.createLocation` / `LocationSyncHandler`), the same
  /// create-locally-then-push shape `SupplierToCompanion` /
  /// `CategoryToCompanion` already use for their own locally-created
  /// rows.
  LocationsCompanion toDriftCompanion() {
    return LocationsCompanion.insert(
      localId: localId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      deletedAt: Value(deletedAt),
    );
  }

  /// Same "no clientReference" status as SupplierToCompanion.toCreateDto
  /// — see [LocationCreateDto]'s own doc comment.
  LocationCreateDto toCreateDto() => LocationCreateDto(name: name);
}

extension LocationResponseDtoToCompanion on LocationResponseDto {
  /// Builds the Locations row directly from the raw response — same
  /// shape as ProductResponseDtoToCompanion.toDriftCompanion: no
  /// Draft/entity round-trip, since this is the pull-sync direction
  /// (a location a desktop companion created, arriving here via
  /// [LocationRepository.syncFromServer]) rather than the
  /// mobile-created direction ([LocationToCompanion] above). localId ==
  /// id, matching every other *ResponseDto.toDomain/toDriftCompanion in
  /// this codebase for the same reason. syncStatus is always settled —
  /// this data only ever gets written here as a direct consequence of a
  /// successful server response, never speculatively ahead of one.
  LocationsCompanion toDriftCompanion() {
    final now = DateTime.now();
    return LocationsCompanion.insert(
      localId: id,
      serverId: Value(id),
      name: name,
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.settled,
      deletedAt: const Value(null),
    );
  }
}
