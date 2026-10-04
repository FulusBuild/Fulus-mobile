import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';
import '../local/secure_storage/secure_storage.dart';
import '../../sync/sync_execution_lease.dart';
import '../../sync/sync_service.dart';
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
    required SyncService syncService,
    required AuthRepository authRepository,
    required SyncExecutionLease executionLease,
    required FulusStaffAccessApi staffAccessApi,
    void Function(AuthUser?)? onSessionChanged,
  })  : _database = database,
        _restoreApi = restoreApi,
        _connection = connection,
        _secureStorage = secureStorage,
        _syncService = syncService,
        _authRepository = authRepository,
        _executionLease = executionLease,
        _staffAccessApi = staffAccessApi,
        _onSessionChanged = onSessionChanged;

  final AppDatabase _database;
  final CloudRestoreApi _restoreApi;
  final FulusConnectionState _connection;
  final SecureStorage _secureStorage;
  final SyncService _syncService;
  final AuthRepository _authRepository;
  final SyncExecutionLease _executionLease;
  final FulusStaffAccessApi _staffAccessApi;
  final void Function(AuthUser?)? _onSessionChanged;

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

      // The restore snapshot is already a complete point-in-time business
      // image. Establish the claimed local identity before enabling sync so
      // any trigger that wakes immediately after setEnabled() sees the same
      // user/location projection the restore just created.
      //
      // Do not make first-device onboarding depend on a second network
      // reconciliation completing synchronously. A transient connectivity or
      // sync failure after a valid restore must not strand the employee on the
      // join screen. The persisted restore cursor and device registration make
      // the local snapshot safe to use; normal sync triggers can retry the
      // follow-up reconciliation in the background.
      await _upsertIdentityProjection(claim);

      await _syncService.enableForRestore();
      unawaited(
        _syncService.reconcileAfterRestore().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            // SyncService owns the readiness transition. Employee onboarding
            // remains successful because the restored local image is durable;
            // a later trigger can retry the cloud reconciliation.
          },
        ),
      );

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

  Future<AuthUser?> refreshExistingAccess({bool force = false, String? businessId}) async {
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
    final resolvedBusinessId = businessId ?? _connection.selectedBusinessId;
    if (resolvedBusinessId == null) return null;
    StaffClaim claim;
    try {
      claim = await _staffAccessApi.getMyAccess(businessId: resolvedBusinessId);
    } on AuthFailure {
      final revokedAt = DateTime.now();
      await (_database.update(_database.users)
            ..where((u) => u.localId.equals(current.id)))
          .write(const UsersCompanion(isActive: Value(false)));
      final employeeByAuth = await (_database.select(_database.employees)
            ..where((e) => e.authUserId.equals(current.id)))
          .getSingleOrNull();
      final employeeByCloud = employeeByAuth == null
          ? await (_database.select(_database.employees)
                ..where((e) => e.cloudUserId.equals(current.id)))
              .getSingleOrNull()
          : null;
      final employeeLocalId =
          employeeByAuth?.localId ?? employeeByCloud?.localId;
      if (employeeLocalId != null) {
        await (_database.update(_database.employees)
              ..where((e) => e.localId.equals(employeeLocalId)))
            .write(
          EmployeesCompanion(
            isActive: const Value(false),
            deletedAt: Value(revokedAt),
            syncStatus: const Value(SyncStatus.settled),
            updatedAt: Value(revokedAt),
          ),
        );
      }
      await (_database.delete(_database.userPermissions)
            ..where((p) => p.userId.equals(current.id)))
          .go();
      await _database.delete(_database.sessions).go();
      _connection.disconnect();
      await _syncService.disable();
      final restored = await _authRepository.restoreSession();
      _onSessionChanged?.call(restored);
      _connection.notifyAccessProjectionChanged();
      return restored;
    }
    if (claim.userId != current.id) {
      throw const AuthFailure.forbidden();
    }
    await _upsertIdentityProjection(claim);
    _lastAccessRefreshAt = DateTime.now();
    _connection.notifyAccessProjectionChanged();
    final restored = await _authRepository.restoreSession();
    _onSessionChanged?.call(restored);
    return restored;
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

      onProgress?.call('Setting up this phone…');
      final deviceId = await _secureStorage.ensureDeviceClientId(Ulid().toString());
      final package = await PackageInfo.fromPlatform();
      await _connection.registerDevice(
        deviceClientId: deviceId,
        deviceName: 'Fulus Mobile',
        platform: Platform.operatingSystem,
        appVersion: package.version,
      );

      await _syncService.enable();
      try {
        await _syncService.reconcileForReadiness();
      } catch (error) {
        _syncService.markReadinessError(error);
        rethrow;
      }
      _syncService.markReady();

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
