import '../entities/location.dart';

/// Architecture Section 4's repository pattern, applied to Locations.
/// Read + pull-sync only, deliberately no create/update method: per
/// Section 7a, locations are configured business-wide (desktop-managed)
/// — the location switcher lets a device VIEW and select among existing
/// locations, not create new ones. If a future phase adds mobile-side
/// location management, that's a real, additive change to this
/// interface, not something this phase should speculatively include
/// ahead of an actual UI that needs it.
abstract class LocationRepository {
  /// Reactive by default (Architecture Section 4) — the location
  /// switcher (Volume 3) needs this to update immediately if the set of
  /// locations changes via a sync, with no manual refresh.
  Stream<List<Location>> watchLocations();

  Future<Location?> getLocationById(String localId);

  /// Pulls the current set of locations from the backend and reconciles
  /// it locally — the concrete direction this data actually flows in
  /// (server -> mobile), mirroring ApprovalPinRepository.
  /// syncApprovalHashes's own replace-based reconciliation rather than
  /// SaleRepository's create-then-push pattern, since this is a pull,
  /// not a push.
  Future<void> syncFromServer();
}
