import '../data/local/database/database.dart';
import 'sync_queue.dart';

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
