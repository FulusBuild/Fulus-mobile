import 'package:drift/drift.dart';

import 'database/database.dart';
import 'database/tables.dart';

/// Persistence boundary for projecting cloud staff access into the local
/// identity/session model.
///
/// The cloud-session coordinator decides *when* access changes. This store
/// owns *how* that remote identity and permission state is represented in
/// local SQLite, including stable identity matching and session reconstruction.
class LocalEmployeeIdentityStore {
  LocalEmployeeIdentityStore(this._db);

  final AppDatabase _db;

  Future<void> project({
    required String userId,
    required String membershipId,
    required String roleName,
    required String fullName,
    required String email,
    required String? locationId,
    required List<String> permissionCodes,
    required String? employeeId,
    required Map<String, dynamic>? employee,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final localLocationId = await _resolveLocalLocationId(locationId);
    final localEmployeeId = await _resolveLocalEmployeeId(
      userId: userId,
      employeeId: employeeId,
      membershipId: membershipId,
    );
    final normalizedFullName =
        fullName.trim().isEmpty ? 'Staff member' : fullName.trim();
    final role = _localRole(roleName);

    await _db.transaction(() async {
      await _upsertUser(
        userId: userId,
        email: email,
        fullName: normalizedFullName,
        role: role,
        now: now,
      );
      await _upsertEmployee(
        localEmployeeId: localEmployeeId,
        userId: userId,
        membershipId: membershipId,
        employeeId: employeeId,
        fullName: normalizedFullName,
        roleName: roleName,
        employee: employee,
        localLocationId: localLocationId,
        now: now,
      );
      await _replacePermissions(
        userId: userId,
        permissionCodes: permissionCodes,
        now: now,
      );
      await _replaceSession(
        userId: userId,
        activeLocationId: localLocationId,
      );
    });
  }

  Future<void> revoke({
    required String userId,
    required DateTime revokedAt,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.users)..where((u) => u.localId.equals(userId)))
          .write(const UsersCompanion(isActive: Value(false)));

      final employee = await _findEmployeeForUser(userId);
      if (employee != null) {
        await (_db.update(_db.employees)
              ..where((e) => e.localId.equals(employee.localId)))
            .write(
          EmployeesCompanion(
            isActive: const Value(false),
            deletedAt: Value(revokedAt),
            syncStatus: const Value(SyncStatus.settled),
            updatedAt: Value(revokedAt),
          ),
        );
      }

      await (_db.delete(_db.userPermissions)
            ..where((p) => p.userId.equals(userId)))
          .go();
      await _db.delete(_db.sessions).go();
    });
  }

  Future<String?> linkedEmployeeLocalId(String userId) async {
    return (await _findEmployeeForUser(userId))?.localId;
  }

  Future<String?> _resolveLocalLocationId(String? cloudLocationId) async {
    if (cloudLocationId == null || cloudLocationId.isEmpty) return null;
    final byServer = await (_db.select(_db.locations)
          ..where((l) => l.serverId.equals(cloudLocationId)))
        .getSingleOrNull();
    if (byServer != null) return byServer.localId;

    final byLocal = await (_db.select(_db.locations)
          ..where((l) => l.localId.equals(cloudLocationId)))
        .getSingleOrNull();
    if (byLocal != null) return byLocal.localId;
    throw StateError('Employee location is not available on this device.');
  }

  Future<String> _resolveLocalEmployeeId({
    required String userId,
    required String? employeeId,
    required String membershipId,
  }) async {
    if (employeeId != null) {
      final byServer = await (_db.select(_db.employees)
            ..where((e) => e.serverId.equals(employeeId)))
          .getSingleOrNull();
      if (byServer != null) return byServer.localId;
    }

    final existing = await _findEmployeeForUser(userId);
    if (existing != null) return existing.localId;

    return employeeId ?? membershipId;
  }

  Future<EmployeeRow?> _findEmployeeForUser(String userId) async {
    final byAuth = await (_db.select(_db.employees)
          ..where((e) => e.authUserId.equals(userId)))
        .getSingleOrNull();
    if (byAuth != null) return byAuth;

    return (_db.select(_db.employees)
          ..where((e) => e.cloudUserId.equals(userId)))
        .getSingleOrNull();
  }

  Future<void> _upsertUser({
    required String userId,
    required String email,
    required String fullName,
    required String role,
    required int now,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO users(
        local_id, username, email, full_name, hashed_password, password_salt,
        login_pin_hash, login_pin_salt, role, is_active,
        failed_login_attempts, locked_until, approval_pin_hash,
        approval_pin_salt, created_at, updated_at
      )
      VALUES (?, NULL, ?, ?, NULL, NULL, NULL, NULL, ?, 1, 0, NULL, NULL, NULL, ?, ?)
      ON CONFLICT(local_id) DO UPDATE SET
        email = excluded.email,
        full_name = excluded.full_name,
        role = excluded.role,
        is_active = 1,
        updated_at = excluded.updated_at
      ''',
      [userId, email, fullName, role, now, now],
    );
  }

  Future<void> _upsertEmployee({
    required String localEmployeeId,
    required String userId,
    required String membershipId,
    required String? employeeId,
    required String fullName,
    required String roleName,
    required String email,
    required Map<String, dynamic>? employee,
    required String? localLocationId,
    required int now,
  }) async {
    final dateHired = employee?['date_hired'] == null
        ? null
        : DateTime.tryParse(employee!['date_hired'].toString())
            ?.millisecondsSinceEpoch;

    await _db.customStatement(
      '''
      INSERT INTO employees(
        id, server_id, membership_id, cloud_user_id, sync_status,
        auth_user_id, full_name, role, department, position, salary,
        phone, email, date_hired, location_id, is_active,
        created_at, updated_at, deleted_at
      )
      VALUES (?, ?, ?, ?, 'settled', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
      ON CONFLICT(id) DO UPDATE SET
        server_id = excluded.server_id,
        membership_id = excluded.membership_id,
        cloud_user_id = excluded.cloud_user_id,
        sync_status = excluded.sync_status,
        auth_user_id = excluded.auth_user_id,
        full_name = excluded.full_name,
        role = excluded.role,
        department = excluded.department,
        position = excluded.position,
        salary = excluded.salary,
        phone = excluded.phone,
        email = excluded.email,
        date_hired = excluded.date_hired,
        location_id = excluded.location_id,
        is_active = 1,
        deleted_at = NULL,
        updated_at = excluded.updated_at
      ''',
      [
        localEmployeeId,
        employeeId,
        membershipId,
        userId,
        userId,
        employee?['full_name']?.toString().trim().isNotEmpty == true
            ? employee!['full_name'].toString()
            : fullName,
        employee?['role']?.toString() ?? roleName,
        employee?['department'],
        employee?['position'],
        employee?['salary'],
        employee?['phone'],
        employee?['email'] ?? email,
        dateHired,
        localLocationId,
        now,
        now,
      ],
    );
  }


  Future<void> _replacePermissions({
    required String userId,
    required List<String> permissionCodes,
    required int now,
  }) async {
    await (_db.delete(_db.userPermissions)
          ..where((p) => p.userId.equals(userId)))
        .go();

    for (final permission in _mapPermissions(permissionCodes)) {
      await _db.customStatement(
        '''
        INSERT INTO user_permissions(user_id, permission, granted_by, granted_at)
        VALUES (?, ?, NULL, ?)
        ON CONFLICT(user_id, permission) DO NOTHING
        ''',
        [userId, permission, now],
      );
    }
  }

  Future<void> _replaceSession({
    required String userId,
    required String? activeLocationId,
  }) async {
    await _db.delete(_db.sessions).go();
    await _db.customStatement(
      'INSERT INTO sessions(id, user_id, active_location_id) VALUES (?, ?, ?)',
      ['current', userId, activeLocationId],
    );
  }

  Set<String> _mapPermissions(List<String> codes) {
    final result = <String>{};
    for (final code in codes) {
      switch (code) {
        case 'audit.read':
          result.add('viewAuditLog');
        case 'business.manage':
        case 'locations.manage':
          result.add('manageSettings');
        case 'backup.manage':
          result.add('manageBackup');
        case 'business.read':
          result.add('viewDashboardStats');
        case 'cash.manage':
        case 'cash.read':
        case 'finance.manage':
        case 'finance.read':
        case 'sales.read':
        case 'customers.read':
        case 'credit.manage':
          result.add('viewMoney');
        case 'catalog.manage':
        case 'inventory.adjust':
        case 'inventory.transfer':
        case 'inventory.read':
          result.add('manageStock');
        case 'reports.read':
          result.add('viewReports');
        case 'employees.manage':
          result.add('manageEmployees');
        case 'returns.approve':
        case 'sales.void':
          result.add('approveWithoutSupervisor');
      }
    }
    return result;
  }

  String _localRole(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'admin':
        return 'owner';
      case 'manager':
        return 'manager';
      case 'cashier':
        return 'cashier';
      default:
        return 'employee';
    }
  }
}
