import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/permission.dart';
import '../local/database/database.dart';
import 'fulus_staff_access_api.dart';

/// Materializes a claimed cloud staff membership into the local offline-first
/// identity model. The cloud auth UUID is deliberately used as Users.localId:
/// sales, shifts and restored snapshots already use the cloud user UUID as
/// their stable cashier/actor identity.
class CrossDeviceEmployeeService {
  CrossDeviceEmployeeService(this._db);

  final AppDatabase _db;

  Future<AuthUser> provision({
    required StaffClaim claim,
    String? displayName,
  }) async {
    final now = DateTime.now();
    final fullName = (displayName ?? claim.fullName).trim();
    if (fullName.isEmpty) {
      throw const FormatException('Employee name is required.');
    }

    final role = _localRole(claim.roleName);
    final employeeId = claim.membershipId;
    final email = claim.email.isEmpty ? null : claim.email;

    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM user_permissions WHERE user_id = ?',
        [claim.userId],
      );
      await _db.customStatement(
        'DELETE FROM employees WHERE auth_user_id = ? AND id <> ?',
        [claim.userId, employeeId],
      );

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
          failed_login_attempts = 0,
          locked_until = NULL,
          updated_at = excluded.updated_at
        ''',
        [
          claim.userId,
          email,
          fullName,
          role.name,
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        ],
      );

      await _db.customStatement(
        '''
        INSERT INTO employees(
          id, auth_user_id, full_name, role, department, position, salary,
          phone, email, date_hired, location_id, is_active,
          created_at, updated_at, deleted_at
        )
        VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL, ?, NULL, ?, 1, ?, ?, NULL)
        ON CONFLICT(id) DO UPDATE SET
          auth_user_id = excluded.auth_user_id,
          full_name = excluded.full_name,
          role = excluded.role,
          email = excluded.email,
          location_id = excluded.location_id,
          is_active = 1,
          deleted_at = NULL,
          updated_at = excluded.updated_at
        ''',
        [
          employeeId,
          claim.userId,
          fullName,
          claim.roleName,
          email,
          claim.locationId,
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch,
        ],
      );

      for (final permission in _mapPermissions(claim.permissionCodes)) {
        await _db.customStatement(
          '''
          INSERT INTO user_permissions(
            user_id, permission, granted_by, granted_at
          )
          VALUES (?, ?, NULL, ?)
          ON CONFLICT(user_id, permission) DO NOTHING
          ''',
          [claim.userId, permission.name, now.millisecondsSinceEpoch],
        );
      }

      await _db.delete(_db.sessions).go();
      await _db.into(_db.sessions).insert(
            SessionsCompanion.insert(
              id: 'current',
              userId: claim.userId,
              activeLocationId: Value(claim.locationId),
            ),
          );
    });

    return AuthUser(
      id: claim.userId,
      fullName: fullName,
      email: email,
      role: role,
      isActive: true,
      hasLoginPin: false,
    );
  }

  AuthRole _localRole(String cloudRole) {
    switch (cloudRole.toLowerCase()) {
      case 'manager':
      case 'admin':
        return AuthRole.manager;
      case 'cashier':
        return AuthRole.cashier;
      default:
        return AuthRole.employee;
    }
  }

  Set<Permission> _mapPermissions(List<String> codes) {
    final result = <Permission>{};
    for (final code in codes) {
      switch (code) {
        case 'audit.read':
          result.add(Permission.viewAuditLog);
        case 'business.manage':
        case 'locations.manage':
          result.add(Permission.manageSettings);
        case 'business.read':
          result.add(Permission.viewDashboardStats);
        case 'cash.manage':
        case 'cash.read':
        case 'finance.manage':
        case 'finance.read':
        case 'sales.read':
        case 'customers.read':
        case 'credit.manage':
          result.add(Permission.viewMoney);
        case 'catalog.manage':
        case 'inventory.adjust':
        case 'inventory.transfer':
        case 'inventory.read':
          result.add(Permission.manageStock);
        case 'reports.read':
          result.add(Permission.viewReports);
        case 'employees.manage':
          result.add(Permission.manageEmployees);
        case 'returns.approve':
        case 'sales.void':
          result.add(Permission.approveWithoutSupervisor);
      }
    }
    return result;
  }
}
