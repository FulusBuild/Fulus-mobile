import '../entities/location.dart';

/// Architecture Section 4's repository pattern, applied to Locations.
abstract class LocationRepository {
  Stream<List<Location>> watchLocations();

  Future<Location?> getLocationById(String localId);

  /// Resolves a cloud location identity back to this device's local identity.
  /// Cross-device business entities store server IDs in the cloud but keep
  /// local foreign keys locally.
  Future<Location?> getLocationByServerId(String serverId);

  Future<Location> createLocation(LocationDraft draft);

  Future<Location> getOrCreateDefaultLocation({required String name});

  Future<void> markSynced({required String localId, required String serverId, String? operationId});

  /// Pulls the current set of locations from the backend and reconciles
  /// them locally — this is a pull, not an outbound write.
  Future<void> syncFromServer();

  /// Applies an authoritative server snapshot without enqueueing an
  /// outbound sync task. Existing local identity is preserved when the
  /// server id is already known; a server-originated location gets a
  /// fresh local identity.
  Future<void> reconcileServerState({
    required String serverId,
    required String name,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies an authoritative server delete without enqueueing an
  /// outbound sync task. Missing local rows are a no-op.
  Future<void> reconcileDeleted(String serverId);
}
