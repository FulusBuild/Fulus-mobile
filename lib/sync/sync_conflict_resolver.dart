import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/database/database.dart';
import '../data/remote/fulus_canonical_reconciler_typed.dart';
import '../data/remote/fulus_connection_state.dart';
import '../data/remote/fulus_sync_api.dart';
import 'sync_execution_lease.dart';

/// Resolves a parked optimistic-concurrency conflict by explicitly accepting
/// the current authoritative cloud version.
///
/// Conflict resolution is part of the same durable sync critical section as
/// automatic reconciliation. Canonical state is fetched while the lease is
/// held, then the local apply starts with the conditional lease UPDATE inside
/// the SQLite transaction. This prevents another runtime from taking over
/// between the canonical read and local write.
class SyncConflictResolver {
  SyncConflictResolver({
    required AppDatabase db,
    required FulusCanonicalTypedReconciler reconciler,
    required FulusCanonicalEntityFetcher canonicalFetcher,
    required FulusConnectionState connectionState,
    required SharedPreferences preferences,
    required SyncExecutionLease executionLease,
  })  : _db = db,
        _reconciler = reconciler,
        _canonicalFetcher = canonicalFetcher,
        _connectionState = connectionState,
        _executionLease = executionLease;

  final AppDatabase _db;
  final FulusCanonicalTypedReconciler _reconciler;
  final FulusCanonicalEntityFetcher _canonicalFetcher;
  final FulusConnectionState _connectionState;
  final SyncExecutionLease _executionLease;

  Future<void> keepCloudVersion(String conflictId) async {
    final conflict = await (_db.select(_db.syncConflictRecords)
          ..where((c) => c.id.equals(conflictId))
          ..where((c) => c.resolvedAt.isNull()))
        .getSingleOrNull();
    if (conflict == null) return;

    final businessId = _connectionState.selectedBusinessId;
    final device = _connectionState.registeredDevice;
    if (businessId == null || device == null || !_connectionState.isDeviceAuthorized) {
      throw StateError('Fulus Cloud is not ready to resolve this conflict.');
    }

    if (!await _executionLease.acquire()) {
      throw StateError('Another Fulus runtime is currently syncing.');
    }

    try {
      // Re-read the conflict only after acquiring the shared lease. The
      // initial UI read can become stale while another runtime resolves or
      // replaces the conflict. Once the lease is held, no other protected
      // resolver or sync cycle can mutate the conflict before this operation.
      final conflict = await (_db.select(_db.syncConflictRecords)
            ..where((c) => c.id.equals(conflictId))
            ..where((c) => c.resolvedAt.isNull()))
          .getSingleOrNull();
      if (conflict == null) return;

      final serverEntityId = await _serverEntityId(
        conflict.entityType,
        conflict.entityLocalId,
      );
      if (serverEntityId == null || serverEntityId.isEmpty) {
        throw StateError('The conflicted record no longer has a server identity.');
      }

      final canonical = await _reconciler.fetchCanonical(
        FulusSyncChange(
          sequence: 0,
          entityType: conflict.entityType,
          entityId: serverEntityId,
          operation: 'upsert',
          payload: null,
          createdAt: conflict.createdAt,
        ),
        businessId: businessId,
        deviceClientId: device.deviceClientId,
      );

      await _db.transaction(() async {
        await _executionLease.ensureHeldForTransaction();
        await _reconciler.applyCanonicalResponse(
          canonical,
          expectedEntityType: conflict.entityType,
          expectedEntityId: serverEntityId,
        );
        await (_db.delete(_db.syncQueueItems)
              ..where((q) => q.id.equals(conflict.operationId)))
            .go();
        await (_db.update(_db.syncConflictRecords)
              ..where((c) => c.id.equals(conflict.id)))
            .write(
          SyncConflictRecordsCompanion(
            resolvedAt: Value(DateTime.now()),
            resolution: const Value('kept_authoritative_cloud_version'),
          ),
        );
      });
    } finally {
      await _executionLease.release();
    }
  }

  /// Keeps the local edit, but rebases its optimistic-concurrency cursor to
  /// the latest server cursor observed by this device. The conflict remains
  /// unresolved until the queued mutation is actually accepted by Cloud.
  Future<void> keepLocalVersion(String conflictId) async {
    final conflict = await (_db.select(_db.syncConflictRecords)
          ..where((c) => c.id.equals(conflictId))
          ..where((c) => c.resolvedAt.isNull()))
        .getSingleOrNull();
    if (conflict == null) return;

    final businessId = _connectionState.selectedBusinessId;
    final device = _connectionState.registeredDevice;
    if (businessId == null || device == null || !_connectionState.isDeviceAuthorized) {
      throw StateError('Fulus Cloud is not ready to retry this conflict.');
    }

    if (!await _executionLease.acquire()) {
      throw StateError('Another Fulus runtime is currently syncing.');
    }

    try {
      // Re-read the conflict only after acquiring the shared lease so this
      // retry cannot operate on a conflict that another runtime already
      // resolved while this call was waiting to acquire the lease.
      final conflict = await (_db.select(_db.syncConflictRecords)
            ..where((c) => c.id.equals(conflictId))
            ..where((c) => c.resolvedAt.isNull()))
          .getSingleOrNull();
      if (conflict == null) return;

      final queue = await (_db.select(_db.syncQueueItems)
            ..where((q) => q.id.equals(conflict.operationId)))
          .getSingleOrNull();
      if (queue == null) {
        throw StateError('The conflicted local change is no longer queued.');
      }

      final serverEntityId = await _serverEntityId(
        conflict.entityType,
        conflict.entityLocalId,
      );
      if (serverEntityId == null || serverEntityId.isEmpty) {
        throw StateError('The conflicted record no longer has a server identity.');
      }

      final canonical = await _canonicalFetcher.fetchCanonicalEntity(
        businessId: businessId,
        entityType: conflict.entityType,
        entityId: serverEntityId,
        deviceClientId: device.deviceClientId,
      );
      final latestSequence = canonical.data['latest_sequence'];
      if (latestSequence is! num || latestSequence < 1) {
        throw StateError('Cloud did not provide a valid conflict rebase cursor.');
      }

      await _db.transaction(() async {
        await _executionLease.ensureHeldForTransaction();
        await (_db.update(_db.syncQueueItems)
              ..where((q) => q.id.equals(conflict.operationId)))
            .write(
          SyncQueueItemsCompanion(
            baseCursor: Value(latestSequence.toInt()),
            syncAttempts: const Value(0),
            lastAttemptedAt: const Value(null),
            lastError: const Value(null),
          ),
        );
      });
    } finally {
      await _executionLease.release();
    }
  }

  Future<String?> _serverEntityId(String entityType, String localId) async {
    switch (entityType) {
      case 'customer':
        return (await (_db.select(_db.customers)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'expense':
        return (await (_db.select(_db.expenses)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'product':
        return (await (_db.select(_db.products)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'category':
        return (await (_db.select(_db.categories)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'supplier':
        return (await (_db.select(_db.suppliers)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'cash_drawer_shift':
        return (await (_db.select(_db.cashDrawerShifts)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'sale':
        return (await (_db.select(_db.sales)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'return':
        return (await (_db.select(_db.returnRequests)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'stock_movement':
        return (await (_db.select(_db.stockMovements)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'income_record':
        return (await (_db.select(_db.incomeRecords)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'expense_category':
        return (await (_db.select(_db.expenseCategories)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'customer_ledger':
        return (await (_db.select(_db.customerLedgerEntries)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      case 'location':
        return (await (_db.select(_db.locations)
                  ..where((t) => t.localId.equals(localId)))
                .getSingleOrNull())
            ?.serverId;
      default:
        return null;
    }
  }
}
