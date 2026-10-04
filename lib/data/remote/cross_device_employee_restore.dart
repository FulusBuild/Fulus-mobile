import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/entities/permission.dart';
import '../local/database/database.dart';
import '../repositories/business_settings_mapper.dart';
import 'cloud_restore_importer.dart';
import 'fulus_staff_access_api.dart';
import '../../sync/sync_execution_lease.dart';

/// Restores a cloud business onto a fresh employee device, while preserving
/// the claimed employee as the authenticated local session instead of turning
/// the employee into an owner.
class CrossDeviceEmployeeRestore {
  CrossDeviceEmployeeRestore(
    this._db, {
    required SyncExecutionLease executionLease,
  }) : _executionLease = executionLease;

  final AppDatabase _db;
  final SyncExecutionLease _executionLease;

  Future<CloudRestoreResult> restore({
    required Map<String, dynamic> snapshot,
    required StaffClaim claim,
    required BusinessSettingsResponseDto settings,
    required AuthRole role,
    void Function(String status)? onProgress,
  }) async {
    if (!await _executionLease.acquire()) {
      throw StateError('Another Fulus runtime is currently syncing.');
    }

    try {
      return await _db.transaction(() async {
        await _executionLease.ensureHeldForTransaction();

        final pending = await _db.select(_db.syncQueueItems).get();
        if (pending.isNotEmpty) {
          throw StateError(
            'Business restore is blocked while ' +
                pending.length.toString() +
                ' outbound sync operation(s) are pending.',
          );
        }
        final conflicts = await _db.select(_db.syncConflictRecords).get();
        if (conflicts.isNotEmpty) {
          throw StateError(
            'Business restore is blocked while ' +
                conflicts.length.toString() +
                ' sync conflict(s) remain unresolved.',
          );
        }

        final now = DateTime.now();
        final fullName = claim.fullName.trim().isEmpty ? 'Staff member' : claim.fullName.trim();

        // Sales and cash-drawer rows reference Users.localId. Seed the
        // claimed cloud identity before importing business rows so its
        // historical activity can satisfy the local foreign key.
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
          [
            claim.userId,
            claim.email,
            fullName,
            role.name,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          ],
        );
        onProgress?.call('Restoring business data…');
        final result = await CloudRestoreImporter(_db).importSnapshot(
          snapshot,
          ownerCloudUserId: claim.userId,
          transactional: false,
          onProgress: onProgress,
        );

        // The generic cloud restore imports staff identities so historical
        // cashier attribution remains valid. On an employee-only device,
        // those identities must remain historical/inactive rather than
        // becoming selectable accounts. Never delete them: sales and other
        // business rows may still reference their local IDs.
        await _db.customStatement(
          '''
          UPDATE users
          SET is_active = 0, updated_at = ?
          WHERE local_id <> ?
          ''',
          [now.millisecondsSinceEpoch, claim.userId],
        );

        await _db.delete(_db.businessSettings).go();
        await _db.into(_db.businessSettings).insert(settings.toDriftCompanion());

        final employee = claim.employee;
        final dateHired = employee?['date_hired'] == null
            ? null
            : DateTime.tryParse(employee!['date_hired'].toString())?.millisecondsSinceEpoch;
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
            claim.employeeId ?? claim.membershipId,
            claim.employeeId,
            claim.membershipId,
            claim.userId,
            claim.userId,
            employee?['full_name']?.toString().trim().isNotEmpty == true
                ? employee!['full_name'].toString()
                : fullName,
            employee?['role']?.toString() ?? claim.roleName,
            employee?['department'],
            employee?['position'],
            employee?['salary'],
            employee?['phone'],
            employee?['email'] ?? claim.email,
            dateHired,
            employee?['location_id'] ?? claim.locationId,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
          ],
        );

        await _db.customStatement(
          'DELETE FROM user_permissions WHERE user_id = ?',
          [claim.userId],
        );

        for (final permission in _mapPermissions(claim.permissionCodes)) {
          await _db.customStatement(
            '''
            INSERT INTO user_permissions(user_id, permission, granted_by, granted_at)
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

        final fkViolations = await _db.customSelect('PRAGMA foreign_key_check').get();
        if (fkViolations.isNotEmpty) {
          throw StateError(
            'Employee restore failed: ' +
                fkViolations.length.toString() +
                ' foreign-key violations.',
          );
        }

        return result;
      });
    } finally {
      await _executionLease.release();
    }
  }

  static BusinessSettingsResponseDto settingsFromSnapshot(
    Map<String, dynamic> snapshot,
  ) {
    final business = snapshot['business'];
    if (business is! Map) {
      throw const FormatException('Restore snapshot did not contain business settings.');
    }
    final data = Map<String, dynamic>.from(business);
    final businessId = data['id']?.toString();
    final businessName = data['name']?.toString().trim();
    if (businessId == null || businessId.isEmpty || businessName == null || businessName.isEmpty) {
      throw const FormatException('Restore snapshot contained incomplete business settings.');
    }

    final currencyCode = data['currency_code']?.toString().toUpperCase();
    final currencySymbol = switch (currencyCode) {
      'NGN' => '₦',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currencyCode ?? '₦',
    };

    return BusinessSettingsResponseDto(
      id: businessId,
      businessName: businessName,
      vatEnabled: data['vat_enabled'] == true,
      vatRate: data['vat_rate'] is num ? (data['vat_rate'] as num).toDouble() : 0,
      currencySymbol: currencySymbol,
      address: data['address']?.toString(),
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      tin: data['tin']?.toString(),
      receiptFooter: data['receipt_footer']?.toString(),
    );
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
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
        case 'backup.manage':
          result.add(Permission.manageBackup);
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
