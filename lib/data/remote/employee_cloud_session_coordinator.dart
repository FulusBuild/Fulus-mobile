import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/database/database.dart';
import '../local/secure_storage/secure_storage.dart';
import '../../sync/sync_config.dart';
import '../../sync/sync_execution_lease.dart';
import '../../sync/sync_triggers.dart';
import 'cross_device_employee_restore.dart';
import 'endpoints/cloud_restore_api.dart';
import 'fulus_connection_state.dart';
import 'fulus_staff_access_api.dart';

/// Owns the complete employee cloud-login lifecycle.
///
/// There is exactly one owner of employee onboarding/readiness:
/// authenticate -> resolve membership -> select business -> restore authorized
/// data -> register this device -> enable/reconcile sync -> expose local session.
///
/// Bootstrap is fenced by FulusConnectionState while this operation runs, so
/// it cannot start a competing registration/restore cycle.
class EmployeeCloudSessionCoordinator {
  EmployeeCloudSessionCoordinator({
    required AppDatabase database,
    required CloudRestoreApi restoreApi,
    required FulusConnectionState connection,
    required SecureStorage secureStorage,
    required SyncConfig syncConfig,
    required SyncTriggers syncTriggers,
    required AuthRepository authRepository,
    required SyncExecutionLease executionLease,
    required FulusStaffAccessApi staffAccessApi,
  })  : _database = database,
        _restoreApi = restoreApi,
        _connection = connection,
        _secureStorage = secureStorage,
        _syncConfig = syncConfig,
        _syncTriggers = syncTriggers,
        _authRepository = authRepository,
        _executionLease = executionLease,
        _staffAccessApi = staffAccessApi;

  final AppDatabase _database;
  final CloudRestoreApi _restoreApi;
  final FulusConnectionState _connection;
  final SecureStorage _secureStorage;
  final SyncConfig _syncConfig;
  final SyncTriggers _syncTriggers;
  final AuthRepository _authRepository;
  final SyncExecutionLease _executionLease;
  final FulusStaffAccessApi _staffAccessApi;

  static const _localCloudBusinessKey = 'fulus_local_cloud_business_id';
  static const _accessRefreshInterval = Duration(seconds: 60);
  DateTime? _lastAccessRefreshAt;

  Future<AuthUser> establish({
    required StaffClaim claim,
    void Function(String status)? onProgress,
  }) async {
    if (claim.userId.isEmpty || claim.businessId.isEmpty) {
      throw const BusinessRuleFailure(
        'Your Fulus employee access is incomplete. Please ask the business owner to resend your invitation.',
      );
    }

    _connection.beginCloudOnboarding();
    try {
      onProgress?.call('Joining your business…');
      await _connection.refresh();
      await _connection.selectBusiness(claim.businessId);

      final snapshot = await _restoreApi.fetchSnapshot(
        businessId: claim.businessId,
      );
      final boundary = snapshot['sync_boundary'];
      if (boundary is! num || boundary.toInt() < 0) {
        throw const FormatException(
          'Business restore did not contain a valid sync boundary.',
        );
      }

      onProgress?.call('Setting up this phone…');
      final deviceId = await _secureStorage.ensureDeviceClientId(Ulid().toString());
      final package = await PackageInfo.fromPlatform();
      await _connection.registerDevice(
        deviceClientId: deviceId,
        deviceName: 'Fulus Mobile',
        platform: Platform.operatingSystem,
        appVersion: package.version,
      );

      onProgress?.call('Restoring your business…');
      final localRole = _localRole(claim.roleName);
      final result = await CrossDeviceEmployeeRestore(
        _database,
        executionLease: _executionLease,
      ).restore(
        snapshot: snapshot,
        claim: claim,
        settings: CrossDeviceEmployeeRestore.settingsFromSnapshot(snapshot),
        role: localRole,
        onProgress: onProgress,
      );

      if (result.totalRows == 0) {
        throw StateError('The cloud business has no restorable business data.');
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setInt(
        'fulus_sync_cursor_' + claim.businessId,
        boundary.toInt(),
      );
      if (!saved) {
        throw StateError('Failed to save the cloud restore boundary.');
      }
      await prefs.setString(_localCloudBusinessKey, claim.businessId);

      onProgress?.call('Finishing setup…');
      await _syncConfig.setEnabled(true);
      try {
        await _syncTriggers.reconcileForReadiness();
      } catch (_) {
        _connection.clearSyncReady();
        rethrow;
      }
      _connection.markSyncReady();

      final employee = await _authRepository.restoreSession();
      if (employee == null ||
          employee.id != claim.userId ||
          !employee.isActive) {
        throw StateError(
          'Employee login was created, but the local session could not be restored.',
        );
      }
      return employee;
    } finally {
      _connection.endCloudOnboarding();
    }
  }

  Future<AuthUser?> refreshExistingAccess({bool force = false}) async {
    final current = _authRepository.currentUser;
    if (current == null) return null;
    final lastRefresh = _lastAccessRefreshAt;
    if (!force &&
        lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < _accessRefreshInterval) {
      return current;
    }
    var employee = await (_database.select(_database.employees)
          ..where((e) => e.authUserId.equals(current.id)))
        .getSingleOrNull();
    employee ??= await (_database.select(_database.employees)
          ..where((e) => e.cloudUserId.equals(current.id)))
        .getSingleOrNull();
    if (employee == null) return null;
    final businessId = _connection.selectedBusinessId;
    if (businessId == null) return null;
    final claim = await _staffAccessApi.getMyAccess(businessId: businessId);
    if (claim.userId != current.id) {
      throw const AuthFailure.forbidden();
    }
    await _upsertIdentityProjection(claim);
    _lastAccessRefreshAt = DateTime.now();
    _connection.notifyAccessProjectionChanged();
    return _authRepository.restoreSession();
  }

  Future<AuthUser> activateExisting({
    required StaffClaim claim,
    void Function(String status)? onProgress,
  }) async {
    final localSettings =
        await _database.select(_database.businessSettings).getSingleOrNull();
    if (localSettings == null || localSettings.id != claim.businessId) {
      return establish(claim: claim, onProgress: onProgress);
    }

    _connection.beginCloudOnboarding();
    try {
      await _connection.refresh();
      await _connection.selectBusiness(claim.businessId);
      await _upsertIdentityProjection(claim);

      onProgress?.call('Setting up this phone…');
      final deviceId = await _secureStorage.ensureDeviceClientId(Ulid().toString());
      final package = await PackageInfo.fromPlatform();
      await _connection.registerDevice(
        deviceClientId: deviceId,
        deviceName: 'Fulus Mobile',
        platform: Platform.operatingSystem,
        appVersion: package.version,
      );

      await _syncConfig.setEnabled(true);
      try {
        await _syncTriggers.reconcileForReadiness();
      } catch (_) {
        _connection.clearSyncReady();
        rethrow;
      }
      _connection.markSyncReady();

      final employee = await _authRepository.restoreSession();
      if (employee == null ||
          employee.id != claim.userId ||
          !employee.isActive) {
        throw StateError('Employee session could not be restored.');
      }
      return employee;
    } finally {
      _connection.endCloudOnboarding();
    }
  }

  Future<void> _upsertIdentityProjection(StaffClaim claim) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final localLocationId = await _resolveLocalLocationId(
      claim.employee?['location_id']?.toString() ?? claim.locationId,
    );
    final localEmployeeId = await _resolveLocalEmployeeId(claim);
    final fullName =
        claim.fullName.trim().isEmpty ? 'Staff member' : claim.fullName.trim();
    final role = _localRole(claim.roleName);

    await _database.customStatement(
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
        now,
        now,
      ],
    );

    final employee = claim.employee;
    final dateHired = employee?['date_hired'] == null
        ? null
        : DateTime.tryParse(employee!['date_hired'].toString())
            ?.millisecondsSinceEpoch;

    await _database.customStatement(
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
        localLocationId,
        now,
        now,
      ],
    );

    await _database.customStatement(
      'DELETE FROM user_permissions WHERE user_id = ?',
      [claim.userId],
    );
    for (final permission in _mapPermissions(claim.permissionCodes)) {
      await _database.customStatement(
        '''
        INSERT INTO user_permissions(user_id, permission, granted_by, granted_at)
        VALUES (?, ?, NULL, ?)
        ON CONFLICT(user_id, permission) DO NOTHING
        ''',
        [claim.userId, permission, now],
      );
    }

    await _database.customStatement('DELETE FROM sessions');
    await _database.customStatement(
      'INSERT INTO sessions(id, user_id, active_location_id) VALUES (?, ?, ?)',
      ['current', claim.userId, localLocationId],
    );
  }

  Future<String?> _resolveLocalLocationId(String? cloudLocationId) async {
    if (cloudLocationId == null || cloudLocationId.isEmpty) return null;
    final byServer = await (_database.select(_database.locations)
          ..where((l) => l.serverId.equals(cloudLocationId)))
        .getSingleOrNull();
    if (byServer != null) return byServer.localId;

    final byLocal = await (_database.select(_database.locations)
          ..where((l) => l.localId.equals(cloudLocationId)))
        .getSingleOrNull();
    if (byLocal != null) return byLocal.localId;
    throw StateError('Employee location is not available on this device.');
  }

  Future<String> _resolveLocalEmployeeId(StaffClaim claim) async {
    if (claim.employeeId != null) {
      final byServer = await (_database.select(_database.employees)
            ..where((e) => e.serverId.equals(claim.employeeId!)))
          .getSingleOrNull();
      if (byServer != null) return byServer.localId;
    }

    final byAuth = await (_database.select(_database.employees)
          ..where((e) => e.authUserId.equals(claim.userId)))
        .getSingleOrNull();
    if (byAuth != null) return byAuth.localId;

    final byCloudUser = await (_database.select(_database.employees)
          ..where((e) => e.cloudUserId.equals(claim.userId)))
        .getSingleOrNull();
    if (byCloudUser != null) return byCloudUser.localId;

    return claim.employeeId ?? claim.membershipId;
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

  AuthRole _localRole(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'admin':
        return AuthRole.owner;
      case 'manager':
        return AuthRole.manager;
      case 'cashier':
        return AuthRole.cashier;
      default:
        return AuthRole.employee;
    }
  }
}
