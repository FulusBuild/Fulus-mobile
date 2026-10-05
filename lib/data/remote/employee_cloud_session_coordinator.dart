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
import '../local/secure_storage/secure_storage.dart';
import '../../sync/sync_execution_lease.dart';
import '../../sync/sync_service.dart';
import '../local/employee_identity_projection_store.dart';
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
    required LocalEmployeeIdentityStore identityStore,
    void Function(AuthUser?)? onSessionChanged,
  })  : _database = database,
        _restoreApi = restoreApi,
        _connection = connection,
        _secureStorage = secureStorage,
        _syncService = syncService,
        _authRepository = authRepository,
        _executionLease = executionLease,
        _staffAccessApi = staffAccessApi,
        _identityStore = identityStore,
        _onSessionChanged = onSessionChanged;

  final AppDatabase _database;
  final CloudRestoreApi _restoreApi;
  final FulusConnectionState _connection;
  final SecureStorage _secureStorage;
  final SyncService _syncService;
  final AuthRepository _authRepository;
  final SyncExecutionLease _executionLease;
  final FulusStaffAccessApi _staffAccessApi;
  final LocalEmployeeIdentityStore _identityStore;
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
      await _identityStore.project(
        userId: claim.userId,
        membershipId: claim.membershipId,
        roleName: claim.roleName,
        fullName: claim.fullName,
        email: claim.email,
        locationId: claim.employee?['location_id']?.toString() ?? claim.locationId,
        permissionCodes: claim.permissionCodes,
        employeeId: claim.employeeId,
        employee: claim.employee,
      );

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
    final employeeLocalId = await _identityStore.linkedEmployeeLocalId(current.id);
    if (employeeLocalId == null) return null;
    final resolvedBusinessId = businessId ?? _connection.selectedBusinessId;
    if (resolvedBusinessId == null) return null;
    StaffClaim claim;
    try {
      claim = await _staffAccessApi.getMyAccess(businessId: resolvedBusinessId);
    } on AuthFailure {
      final revokedAt = DateTime.now();
      await _identityStore.revoke(userId: current.id, revokedAt: revokedAt);
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
    await _identityStore.project(
      userId: claim.userId,
      businessId: claim.businessId,
      membershipId: claim.membershipId,
      roleName: claim.roleName,
      fullName: claim.fullName,
      email: claim.email,
      locationId: claim.employee?['location_id']?.toString() ?? claim.locationId,
      permissionCodes: claim.permissionCodes,
      employeeId: claim.employeeId,
      employee: claim.employee,
    );
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
      await _syncService.reconcileForReadiness();

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
