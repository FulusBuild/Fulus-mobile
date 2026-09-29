import 'package:drift/drift.dart';

import '../../domain/entities/auth_user.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/entities/permission.dart';
import '../local/database/database.dart';
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

        onProgress?.call('Restoring business data…');
        final result = await CloudRestoreImporter(_db).importSnapshot(
          snapshot,
          ownerCloudUserId: claim.userId,
          transactional: false,
          onProgress: onProgress,
        );

        await _db.delete(_db.businessSettings).go();
        await _db.into(_db.businessSettings).insert(settings.toDriftCompanion());

        final now = DateTime.now();
        final fullName = claim.fullName.trim().isEmpty ? 'Staff member' : claim.fullName.trim();

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
            claim.membershipId,
            claim.userId,
            fullName,
            claim.roleName,
            claim.email,
            claim.locationId,
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
