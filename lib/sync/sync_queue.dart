import 'package:ulid/ulid.dart';

import '../data/local/database/database.dart';
import '../data/local/database/tables.dart';

/// Architecture Section 8's three priority lanes, named as constants
/// rather than a raw int at each call site — 0 is highest priority
/// (processed first), matching SyncQueueItems.priority's own comment in
/// tables.dart.
abstract final class SyncPriority {
  /// Sales and payments — Section 8: "the core trust promise."
  static const salesAndPayments = 0;

  /// Stock movements, customer/credit writes — still core, but not
  /// money that's already changed hands.
  static const stockAndCustomerWrites = 1;

  /// Product photo uploads, bulk import — explicitly allowed to lag
  /// behind the other two lanes on a poor connection (Section 8).
  static const photosAndBulkImport = 2;
}

/// One queued unit of sync work. A thin, typed wrapper around exactly
/// the columns SyncQueueItems (tables.dart) needs — kept separate from
/// that Drift row type deliberately, so callers outside data/ (a
/// repository, say) can construct one without importing Drift at all.
class SyncTask {
  const SyncTask({
    required this.entityType,
    required this.entityLocalId,
    required this.operation,
    required this.priority,
  });

  /// Architecture Section 4's own example call:
  /// `_syncQueue.enqueue(SyncTask.createSale(localId))`.
  factory SyncTask.createSale(String localId) => SyncTask(
        entityType: 'sale',
        entityLocalId: localId,
        operation: 'create',
        priority: SyncPriority.salesAndPayments,
      );

  final String entityType;
  final String entityLocalId;
  final String operation; // 'create' | 'update' | 'delete'
  final int priority;
}

/// The enqueue side of Architecture Section 8's sync engine — a
/// repository calls `enqueue()` and returns immediately, per Section
/// 4's rule that a write-repository method never awaits the network.
///
/// Deliberately does NOT include any processing/draining logic in this
/// checkpoint: no connectivity listener, no WorkManager registration, no
/// retry/backoff, no syncAttempts-based "needs attention" demotion.
/// Section 8 specifies all of that for a genuine background engine
/// (`sync/sync_engine.dart`) that reads from the same SyncQueueItems
/// table this class writes to — that engine doesn't exist yet. This
/// class's scope stops at "the write is durably queued," which is
/// exactly as far as the repository layer (Section 4) itself needs to
/// reach.
class SyncQueue {
  SyncQueue(this._db);

  final AppDatabase _db;

  Future<void> enqueue(SyncTask task) async {
    await _db.into(_db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: Ulid().toString(),
            entityType: task.entityType,
            entityLocalId: task.entityLocalId,
            operation: task.operation,
            priority: task.priority,
            enqueuedAt: DateTime.now(),
          ),
        );
  }
}
