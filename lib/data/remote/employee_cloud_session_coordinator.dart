import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/database/database.dart';
import '../local/secure_storage/secure_storage.dart';
import '../sync/sync_config.dart';
import '../sync/sync_execution_lease.dart';
import '../sync/sync_triggers.dart';
import 'api_client.dart';
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
    required ApiClient apiClient,
    required CloudRestoreApi restoreApi,
    required FulusConnectionState connection,
    required SecureStorage secureStorage,
    required SyncConfig syncConfig,
    required SyncTriggers syncTriggers,
    required AuthRepository authRepository,
    required SyncExecutionLease executionLease,
  })  : _database = database,
        _apiClient = apiClient,
        _restoreApi = restoreApi,
        _connection = connection,
        _secureStorage = secureStorage,
        _syncConfig = syncConfig,
        _syncTriggers = syncTriggers,
        _authRepository = authRepository,
        _executionLease = executionLease;

  final AppDatabase _database;
  final ApiClient _apiClient;
  final CloudRestoreApi _restoreApi;
  final FulusConnectionState _connection;
  final SecureStorage _secureStorage;
  final SyncConfig _syncConfig;
  final SyncTriggers _syncTriggers;
  final AuthRepository _authRepository;
  final SyncExecutionLease _executionLease;

  static const _localCloudBusinessKey = 'fulus_local_cloud_business_id';

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

  AuthRole _localRole(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'manager':
      case 'admin':
        return AuthRole.manager;
      case 'cashier':
        return AuthRole.cashier;
      default:
        return AuthRole.employee;
    }
  }
}
