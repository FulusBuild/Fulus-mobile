import 'package:drift/drift.dart';

import '../local/database/database.dart';
import 'cloud_restore_importer.dart';

/// Applies an authoritative cloud snapshot during cursor-too-old recovery.
///
/// Recovery is intentionally destructive for cloud-owned business rows, but
/// only runs after the caller proves that no outbound mutation or unresolved
/// conflict would be destroyed. The authenticated local owner/session is
/// recreated from the pre-bootstrap identity after the snapshot transaction
/// completes, so process death rolls the whole bootstrap back atomically.
class CloudSyncBootstrapCoordinator {
  CloudSyncBootstrapCoordinator(this._db);

  final AppDatabase _db;

  Future<int> bootstrap({required Map<String, dynamic> snapshot}) async {
    final boundary = snapshot['sync_boundary'];
    if (boundary is! num || boundary.toInt() < 0) {
      throw const FormatException('Fulus Cloud bootstrap snapshot has no valid sync boundary.');
    }

    return _db.transaction(() async {
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

      // The snapshot importer owns the cloud business tables. It is deliberately
      // run inside this outer transaction so a process death or import failure
      // restores the previous local state instead of leaving a half-bootstrap.
      await CloudRestoreImporter(_db).importSnapshot(
        snapshot,
        ownerCloudUserId: ownerId,
        transactional: false,
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

      await _db.into(_db.users).insert(
        UsersCompanion.insert(
          localId: ownerId,
          fullName: ownerName,
          email: Value(ownerEmail),
          role: localRole,
          isActive: const Value(true),
          createdAt: user.createdAt,
          updatedAt: now,
        ),
      );
      await _db.delete(_db.sessions).go();
      await _db.into(_db.sessions).insert(
        SessionsCompanion.insert(
          id: 'current',
          userId: ownerId,
          activeLocationId: Value(activeLocationId),
        ),
      );

      return boundary.toInt();
    });
  }
}
