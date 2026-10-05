import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';
import '../repositories/business_settings_mapper.dart';
import 'cloud_restore_importer.dart';
import '../../sync/sync_execution_lease.dart';

/// Coordinates reinstall recovery around the importer's transactional restore.
///
/// The coordinator deliberately keeps the entire local restore inside one
/// outer Drift transaction. The importer uses an inner transaction/savepoint;
/// settings and owner/session reconstruction are then committed only when the
/// outer transaction commits successfully.
class CloudRestoreCoordinator {
  CloudRestoreCoordinator(this._db, {required SyncExecutionLease executionLease})
      : _executionLease = executionLease;

  final AppDatabase _db;
  final SyncExecutionLease _executionLease;

  Future<CloudRestoreResult> restore({
    required Map<String, dynamic> snapshot,
    required String ownerCloudUserId,
    required String ownerEmail,
    required BusinessSettingsResponseDto settings,
    void Function(String status)? onProgress,
  }) async {
    if (!await _executionLease.acquireMaintenance()) {
      throw StateError('Fulus is busy finishing another sync. Please try restoring again.');
    }
    try {
      return await _db.transaction(() async {
        await _executionLease.ensureMaintenanceHeldForTransaction();
      onProgress?.call('Preparing local database restore…');

      // Never silently destroy locally queued work or unresolved conflicts.
      // A restore replaces the local business image; carrying those records
      // across would either lose offline mutations or replay them against a
      // different authoritative state. Require the caller to drain/resolve
      // them first. The check is inside the same transaction as the restore
      // so a concurrent enqueue cannot race past the guard.
      final pendingQueueCount = await (_db.select(_db.syncQueueItems)).get();
      if (pendingQueueCount.isNotEmpty) {
        throw StateError(
          'Cloud restore is blocked while ${pendingQueueCount.length} '
          'outbound sync operation(s) are pending. Sync them before restoring.',
        );
      }
      final conflictCount = await (_db.select(_db.syncConflictRecords)).get();
      if (conflictCount.isNotEmpty) {
        throw StateError(
          'Cloud restore is blocked while ${conflictCount.length} '
          'sync conflict(s) remain unresolved. Resolve them before restoring.',
        );
      }

      // Restored sales reference the cloud cashier identity through the
      // local Users foreign key. On a fresh installation the owner row does
      // not exist yet, so seed the authenticated owner before importing
      // business rows. _normalizeOwner() still performs the final session
      // normalization after the complete snapshot has been imported.
      await _ensureOwnerIdentity(
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: ownerEmail,
        snapshot: snapshot,
      );

      final result = await CloudRestoreImporter(_db).importSnapshot(
        snapshot,
        ownerCloudUserId: ownerCloudUserId,
        transactional: false,
        onProgress: onProgress,
      );

      onProgress?.call('Restoring business settings…');
      await _db.delete(_db.businessSettings).go();
      await _db.into(_db.businessSettings).insert(settings.toDriftCompanion());
      onProgress?.call('Restoring owner session…');
      await _normalizeOwner(
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: ownerEmail,
        snapshot: snapshot,
      );

      onProgress?.call('Running final database verification…');
      final fkViolations = await _db.customSelect('PRAGMA foreign_key_check').get();
      if (fkViolations.isNotEmpty) {
        throw StateError(
          'Restore verification failed: ${fkViolations.length} foreign-key violations were detected.',
        );
      }

      onProgress?.call('Committing restored business…');
      return result;
      });
    } finally {
      await _executionLease.releaseMaintenance();
    }
  }

  Future<void> _ensureOwnerIdentity({
    required String ownerCloudUserId,
    required String ownerEmail,
    required Map<String, dynamic> snapshot,
  }) async {
    final profile = snapshot['profile'];
    final profileName = profile is Map
        ? profile['full_name']?.toString().trim()
        : null;
    final fullName = profileName?.isNotEmpty == true ? profileName! : 'Owner';

    final membership = snapshot['membership'];
    final cloudRole = membership is Map
        ? membership['role_name']?.toString().toLowerCase()
        : null;
    final localRole = cloudRole == 'admin' ? AuthRole.manager : AuthRole.owner;

    final existing = await (_db.select(_db.users)
          ..where((u) => u.localId.equals(ownerCloudUserId)))
        .getSingleOrNull();
    if (existing != null) return;

    final now = DateTime.now();
    await _db.into(_db.users).insert(
      UsersCompanion.insert(
        localId: ownerCloudUserId,
        fullName: fullName,
        email: Value(ownerEmail),
        role: localRole,
        isActive: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _normalizeOwner({
    required String ownerCloudUserId,
    required String ownerEmail,
    required Map<String, dynamic> snapshot,
  }) async {
    await _ensureOwnerIdentity(
      ownerCloudUserId: ownerCloudUserId,
      ownerEmail: ownerEmail,
      snapshot: snapshot,
    );

    final profile = snapshot['profile'];
    final profileName = profile is Map
        ? profile['full_name']?.toString().trim()
        : null;
    final fullName = profileName?.isNotEmpty == true ? profileName! : 'Owner';
    final membership = snapshot['membership'];
    final cloudRole = membership is Map
        ? membership['role_name']?.toString().toLowerCase()
        : null;
    final localRole = cloudRole == 'admin' ? AuthRole.manager : AuthRole.owner;

    await (_db.update(_db.users)
          ..where((u) => u.localId.equals(ownerCloudUserId)))
        .write(
      UsersCompanion(
        email: Value(ownerEmail),
        fullName: Value(fullName),
        role: Value(localRole),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // The generic staff importer creates an Employee row for every cloud
    // membership. The authenticated restoring account is represented by the
    // local session instead, so remove its synthetic employee row.
    await (_db.delete(_db.employees)
          ..where((e) => e.authUserId.equals(ownerCloudUserId)))
        .go();

    await _db.delete(_db.sessions).go();
    await _db.into(_db.sessions).insert(
      SessionsCompanion.insert(
        id: 'current',
        userId: ownerCloudUserId,
        activeLocationId: const Value(null),
      ),
    );
  }
}
