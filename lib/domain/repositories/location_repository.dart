import '../entities/location.dart';

/// Architecture Section 4's repository pattern, applied to Locations.
/// Originally read + pull-sync only, on the reasoning that Section 7a's
/// locations are configured business-wide from a desktop companion —
/// but that reasoning assumed a desktop companion always exists, which
/// isn't true for a mobile-only business (Volume 1: mobile IS the
/// business system, desktop is an optional companion, not a
/// requirement). [createLocation] and [getOrCreateDefaultLocation]
/// close that gap: mobile can create a location directly now, syncing
/// it up the same create-locally-then-push way
/// SupplierRepository/CategoryRepository already do for their own
/// entities, while [syncFromServer] keeps pulling down anything a
/// desktop companion creates on its own. Both directions are expected
/// to coexist from here on — a location can originate on either side.
abstract class LocationRepository {
  /// Reactive by default (Architecture Section 4) — the location
  /// switcher (Volume 3) needs this to update immediately if the set of
  /// locations changes via a sync, with no manual refresh.
  Stream<List<Location>> watchLocations();

  Future<Location?> getLocationById(String localId);

  /// Creates [draft] locally (`pending`) and enqueues it for push-sync —
  /// the same create-locally-then-push shape
  /// SupplierRepository.createSupplier / CategoryRepository.createCategory
  /// already use for their own entities. Returns the created [Location]
  /// immediately; the caller doesn't wait on the network (Architecture's
  /// repository layer never awaits network inside a write method).
  Future<Location> createLocation(LocationDraft draft);

  /// Get-or-create, matching DraftCartRepository.getOrCreateDraftCart's
  /// naming convention for the same idempotent shape: if any
  /// non-deleted location already exists — created locally by a prior
  /// call, created through the location-management screen, or synced
  /// down from a desktop companion — returns the earliest one (oldest
  /// `createdAt`) unchanged. Otherwise creates one via [createLocation]
  /// using [name]. This is the mechanism behind Decision 21's
  /// "single-location business has exactly one row, created silently at
  /// onboarding, no location UI ever surfacing" precedent (tables.dart's
  /// own doc comment on the Locations table) — see
  /// `domain/usecases/active_location_resolver.dart` for where this
  /// actually gets called from.
  Future<Location> getOrCreateDefaultLocation({required String name});

  /// Marks a locally-created location as synced once
  /// LocationSyncHandler's push succeeds — same shape and same caller
  /// contract (the sync handler, never feature code directly) as every
  /// other *Repository.markSynced in this codebase
  /// (SupplierRepository, CategoryRepository).
  Future<void> markSynced({required String localId, required String serverId});

  /// Pulls the current set of locations from the backend and reconciles
  /// it locally — the concrete direction this data actually flows in
  /// (server -> mobile), mirroring ApprovalPinRepository.
  /// syncApprovalHashes's own replace-based reconciliation rather than
  /// SaleRepository's create-then-push pattern, since this is a pull,
  /// not a push.
  Future<void> syncFromServer();
}
