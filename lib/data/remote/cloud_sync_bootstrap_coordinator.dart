import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../local/database/database.dart';
import 'cloud_restore_importer.dart';
import '../../sync/sync_execution_lease.dart';

/// Applies an authoritative cloud snapshot during cursor-too-old recovery.
///
/// Recovery is intentionally destructive for cloud-owned business rows, but
/// only runs after the caller proves that no outbound mutation or unresolved
/// conflict would be destroyed. The authenticated local owner/session is
/// recreated from the pre-bootstrap identity after the snapshot transaction
/// completes, so process death rolls the whole bootstrap back atomically.
class CloudSyncBootstrapCoordinator {
  CloudSyncBootstrapCoordinator(this._db, {required SyncExecutionLease executionLease})
      : _executionLease = executionLease;

  final AppDatabase _db;
  final SyncExecutionLease _executionLease;

  Future<int> bootstrap({required Map<String, dynamic> snapshot}) async {
    final boundary = snapshot['sync_boundary'];
    if (boundary is! num || boundary.toInt() < 0) {
      throw const FormatException('Fulus Cloud bootstrap snapshot has no valid sync boundary.');
    }

    return _db.transaction(() async {
      await _executionLease.ensureHeldForTransaction();

      final session = await (_db.select(_db.sessions)
            ..where((s) => s.id.equals('current')))
          .getSingleOrNull();
      if (session == null) {
        throw StateError('Cannot bootstrap Cloud Sync without a local authenticated session.');
      }

      final user = await (_db.select(_db.users)
            ..where((u) => u.localId.equals(session.userId)))
          .getSingleOrNull();
      if (user == null) {
        throw StateError('Cannot bootstrap Cloud Sync without the active local user.');
      }

      final ownerId = user.localId;
      final ownerEmail = user.email;
      final ownerName = user.fullName;
      final activeLocationId = session.activeLocationId;

      // Final recovery safety gate: this is intentionally inside the
      // transaction that will replace cloud-owned rows. Re-check the
      // destructive-recovery preconditions inside the same
      // database transaction that replaces cloud-owned rows. The caller's
      // preflight closes the common case, but a local mutation can be queued
      // between that read and bootstrap. Drift serializes operations on this
      // database executor, so keeping this final gate inside the bootstrap
      // transaction prevents recovery from importing a snapshot over a newly
      // queued local mutation.
      final pending = await _db.select(_db.syncQueueItems).get();
      if (pending.isNotEmpty) {
        throw StateError(
          'Cloud Sync recovery cannot replace local state while new outbound work is queued.',
        );
      }
      final unresolvedConflicts = await (_db.select(_db.syncConflictRecords)
            ..where((c) => c.resolvedAt.isNull()))
          .get();
      if (unresolvedConflicts.isNotEmpty) {
        throw StateError(
          'Cloud Sync recovery cannot replace local state while an unresolved conflict exists.',
        );
      }

      // The snapshot importer owns the cloud business tables. It is deliberately
      // run inside this outer transaction so a process death or import failure
      // restores the previous local state instead of leaving a half-bootstrap.
      await CloudRestoreImporter(_db).importSnapshot(
        snapshot,
        ownerCloudUserId: ownerId,
        transactional: false,
        preserveUnexportedLocalTables: true,
      );

      // users/sessions are device-local authentication state and are not part
      // of the cloud snapshot. Recreate the active identity after the importer
      // has replaced cloud-owned business rows.
      final membership = snapshot['membership'];
      final cloudRole = membership is Map
          ? membership['role_name']?.toString().toLowerCase()
          : null;
      final localRole = cloudRole == 'admin' ? AuthRole.manager : AuthRole.owner;
      final now = DateTime.now();

      await (_db.update(_db.users)..where((u) => u.localId.equals(ownerId))).write(
        UsersCompanion(
          fullName: Value(ownerName),
          email: Value(ownerEmail),
          role: Value(localRole),
          isActive: const Value(true),
          updatedAt: Value(now),
        ),
      );

      // The authoritative snapshot may legitimately no longer contain the
      // location that was active before recovery (for example after that
      // location was deleted or after switching businesses). Never reinsert
      // a stale foreign key into the rebuilt session; the normal location
      // resolver can select a valid active location on the next app pass.
      final restoredLocationId = activeLocationId == null
          ? null
          : await (_db.select(_db.locations)
                ..where((location) => location.localId.equals(activeLocationId)))
              .getSingleOrNull()
              .then((location) => location?.localId);

      await _db.delete(_db.sessions).go();
      await _db.into(_db.sessions).insert(
        SessionsCompanion.insert(
          id: 'current',
          userId: ownerId,
          activeLocationId: Value(restoredLocationId),
        ),
      );

      return boundary.toInt();
    });
  }
}
