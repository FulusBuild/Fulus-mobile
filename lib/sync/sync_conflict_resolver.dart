import '../data/local/database/database.dart';
import '../data/remote/fulus_canonical_reconciler_typed.dart';
import '../data/remote/fulus_connection_state.dart';
import '../data/remote/fulus_sync_api.dart';

/// Resolves a parked optimistic-concurrency conflict by explicitly accepting
/// the current authoritative cloud version.
///
/// The original local mutation is removed only after canonical reconciliation
/// succeeds. If the app dies between those two steps, the same canonical read
/// can safely be replayed on the next attempt.
class SyncConflictResolver {
  SyncConflictResolver({
    required AppDatabase db,
    required FulusCanonicalTypedReconciler reconciler,
    required FulusConnectionState connectionState,
  })  : _db = db,
        _reconciler = reconciler,
        _connectionState = connectionState;

  final AppDatabase _db;
  final FulusCanonicalTypedReconciler _reconciler;
  final FulusConnectionState _connectionState;

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

    // The sequence is deliberately synthetic: reconciliation uses the entity
    // identity to fetch canonical state. Cursor acknowledgement belongs to
    // FulusSyncCoordinator, not to a manual conflict-resolution action.
    await _reconciler.reconcile(
      FulusSyncChange(
        sequence: 0,
        entityType: conflict.entityType,
        entityId: conflict.entityLocalId,
        operation: 'upsert',
        payload: null,
        createdAt: conflict.createdAt,
      ),
      businessId: businessId,
      deviceClientId: device.deviceClientId,
    );

    await _db.transaction(() async {
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
  }
}
