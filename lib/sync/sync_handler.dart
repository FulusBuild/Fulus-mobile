import '../data/local/database/database.dart';

/// Raised when a queued write is valid but depends on another queued entity
/// becoming cloud-backed first (for example a sale whose product has not yet
/// received its server ID). This is not a failed backup and should not count
/// as an exhausted retry; the engine should leave it queued and continue with
/// lower-priority dependency work in the same drain pass.
class SyncDependencyDeferred implements Exception {
  const SyncDependencyDeferred(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One handler per entityType, registered into SyncEngine's map. The
/// engine itself has zero entity-specific logic — it drains the queue
/// in priority/age order and delegates each item to whichever handler
/// is registered for that item's entityType (SyncEngine.runOnce).
///
/// Implementations throw on failure — a [Failure] from
/// core/errors/failure.dart where the failure came through the API
/// layer (matching every other data-layer boundary in this codebase),
/// or any other exception for a failure that never reached the API at
/// all. SyncEngine itself decides what a given thrown object means for
/// the queue item (retry-eligible vs. immediately needs attention), not
/// the handler — see sync_engine.dart's own comment on that split.
abstract class SyncHandler {
  Future<void> sync(SyncQueueItem item);
}
