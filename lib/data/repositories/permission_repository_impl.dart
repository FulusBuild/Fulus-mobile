import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/permission.dart';
import '../../domain/repositories/permission_repository.dart';
import '../local/database/database.dart';

class PermissionRepositoryImpl implements PermissionRepository {
  PermissionRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<Set<Permission>> getPermissions(String userId) async {
    final rows = await (_db.select(
      _db.userPermissions,
    )..where((p) => p.userId.equals(userId))).get();
    return rows.map((r) => r.permission).toSet();
  }

  @override
  Future<bool> hasPermission({
    required String userId,
    required AuthRole role,
    required Permission permission,
  }) async {
    // Owner's exemption is structural, not a lookup — see this
    // repository's own interface doc comment on why this never
    // consults UserPermissions for an owner at all.
    if (role == AuthRole.owner) return true;
    final row = await (_db.select(_db.userPermissions)
          ..where((p) => p.userId.equals(userId) & p.permission.equalsValue(permission)))
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> setPermissions({
    required String userId,
    required Set<Permission> permissions,
    required String grantedBy,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      // Full replace, not incremental — matches this method's own doc
      // comment. Deleting and re-inserting inside one transaction keeps
      // a reader from ever observing a half-updated set.
      await (_db.delete(_db.userPermissions)..where((p) => p.userId.equals(userId))).go();
      for (final permission in permissions) {
        await _db.into(_db.userPermissions).insert(
              UserPermissionsCompanion.insert(
                userId: userId,
                permission: permission,
                grantedBy: Value(grantedBy),
                grantedAt: now,
              ),
            );
      }
    });
  }

  @override
  Future<void> seedDefaultsForNewAccount({
    required String userId,
    required AuthRole role,
    required String grantedBy,
  }) {
    return setPermissions(
      userId: userId,
      permissions: Permission.defaultsForRole(role),
      grantedBy: grantedBy,
    );
  }
}
