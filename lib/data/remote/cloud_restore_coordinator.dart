import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_settings.dart';
import '../local/database/database.dart';
import '../repositories/business_settings_mapper.dart';
import 'cloud_restore_importer.dart';

/// Coordinates reinstall recovery around the importer's transactional restore.
///
/// The coordinator deliberately keeps the entire local restore inside one
/// outer Drift transaction. The importer uses an inner transaction/savepoint;
/// settings and owner/session reconstruction are then committed only when the
/// outer transaction commits successfully.
class CloudRestoreCoordinator {
  CloudRestoreCoordinator(this._db);

  final AppDatabase _db;

  Future<CloudRestoreResult> restore({
    required Map<String, dynamic> snapshot,
    required String ownerCloudUserId,
    required String ownerEmail,
    required BusinessSettingsResponseDto settings,
  }) async {
    return _db.transaction(() async {
      final result = await CloudRestoreImporter(_db).importSnapshot(
        snapshot,
        ownerCloudUserId: null,
        transactional: false,
      );

      await _db.delete(_db.businessSettings).go();
      await _db.into(_db.businessSettings).insert(settings.toDriftCompanion());
      await _normalizeOwner(
        ownerCloudUserId: ownerCloudUserId,
        ownerEmail: ownerEmail,
        snapshot: snapshot,
      );

      final fkViolations = await _db.customSelect('PRAGMA foreign_key_check').get();
      if (fkViolations.isNotEmpty) {
        throw StateError(
          'Restore verification failed: ${fkViolations.length} foreign-key violations were detected.',
        );
      }

      return result;
    });
  }

  Future<void> _normalizeOwner({
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
    // The local auth model has no `admin` role. Map a cloud administrator to
    // the least-privileged local management role and preserve their explicit
    // cloud-derived UserPermissions instead of silently upgrading them to the
    // structurally unrestricted local owner role.
    final localRole = cloudRole == 'admin' ? AuthRole.manager : AuthRole.owner;

    var owner = await (_db.select(_db.users)
          ..where((u) => u.localId.equals(ownerCloudUserId)))
        .getSingleOrNull();

    // Restore snapshots intentionally do not export the device-local `users`
    // table. The importer therefore cannot create the authenticated owner
    // while it is reconstructing staff (the owner is explicitly excluded from
    // that staff loop). Create the owner identity here, before normalizing it,
    // using the stable cloud user id as the local identity id. This makes the
    // restored session self-contained on a fresh installation rather than
    // requiring an old local user row to survive the restore.
    if (owner == null) {
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
      owner = await (_db.select(_db.users)
            ..where((u) => u.localId.equals(ownerCloudUserId)))
          .getSingle();
    }

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
