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

extension LocationResponseDtoToCompanion on LocationResponseDto {
  /// Builds the Locations row directly from the raw response — same
  /// shape as ProductResponseDtoToCompanion.toDriftCompanion: no
  /// Draft/entity round-trip, since a Location only ever originates
  /// server-side (LocationRepository deliberately has no create method
  /// — see its own doc comment). localId == id, matching every other
  /// *ResponseDto.toDomain/toDriftCompanion in this codebase for the
  /// same reason. syncStatus is always settled — this data only ever
  /// gets written here as a direct consequence of a successful server
  /// response, never speculatively ahead of one.
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
