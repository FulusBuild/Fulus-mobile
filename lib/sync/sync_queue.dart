import 'dart:async';

import 'package:ulid/ulid.dart';

import '../data/local/database/database.dart';

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

  factory SyncTask.createCustomer(String localId) => SyncTask(
        entityType: 'customer',
        entityLocalId: localId,
        operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
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
/// The actual draining/retry engine is sync_engine.dart (SyncEngine),
/// which reads from the same SyncQueueItems table this class writes to.
/// This class's own scope stays at "the write is durably queued" plus
/// (via [setOnEnqueued]) nudging that engine to try immediately when a
/// caller's told it to — it does not itself decide retry/backoff or
/// priority processing order, that's entirely SyncEngine's job.
class SyncQueue {
  SyncQueue(this._db);

  final AppDatabase _db;
  Future<void> Function()? _onEnqueued;

  /// Wires Architecture Section 8's fourth trigger ("new item enqueued
  /// while already online") — deliberately a setter, called once from
  /// bootstrap.dart AFTER the full object graph exists, rather than a
  /// constructor parameter. The natural owner of "attempt a sync now"
  /// is SyncTriggers, which wraps SyncEngine, which dispatches to
  /// SaleSyncHandler, which depends on SaleRepository — and
  /// SaleRepositoryImpl itself depends on THIS SyncQueue. Requiring the
  /// callback at construction time would make that a genuine
  /// construction-order cycle; a setter lets every object in the graph
  /// exist first and gets wired together only afterward.
  void setOnEnqueued(Future<void> Function() callback) {
    _onEnqueued = callback;
  }

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

    // Deliberately NOT awaited: enqueue() must still return immediately
    // regardless of whether a sync attempt is already running or how
    // long one takes (Architecture Section 4's rule against a write
    // method ever awaiting the network applies transitively here too —
    // the caller of enqueue() is a repository's write method). Whether
    // this callback actually attempts anything right now, versus a
    // no-op while offline, is entirely up to whatever bootstrap.dart
    // wires in here — this class has no opinion on connectivity.
    final callback = _onEnqueued;
    if (callback != null) {
      unawaited(callback());
    }
  }
}
