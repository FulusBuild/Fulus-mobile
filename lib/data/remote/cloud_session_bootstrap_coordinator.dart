import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ulid/ulid.dart';

import '../../core/config/supabase_config.dart';
import 'api_client.dart';
import 'cloud_sync_recovery.dart';
import 'employee_cloud_session_coordinator.dart';
import 'fulus_connection_state.dart';
import 'endpoints/auth_api.dart';
import '../repositories/auth_repository_impl.dart';
import '../local/secure_storage/secure_storage.dart';
import '../../sync/sync_config.dart';

/// Owns the cloud/session/device/bootstrap lifecycle used by SyncService.
///
/// This component deliberately contains lifecycle policy, while [bootstrap]
/// remains responsible for dependency construction and wiring. SyncService
/// is the only caller-facing boundary for entering this coordinator.
class CloudSessionBootstrapCoordinator {
  CloudSessionBootstrapCoordinator({
    required AuthApi authApi,
    required ApiClient apiClient,
    required SyncConfig syncConfig,
    required SharedPreferences syncPreferences,
    required AuthRepositoryImpl authRepository,
    required SecureStorage secureStorage,
    required FulusConnectionState connectionState,
    required EmployeeCloudSessionCoordinator employeeCloudSessionCoordinator,
    required CloudSyncRecovery syncRecovery,
    required Future<void> Function() reconcileForReadiness,
  })  : _authApi = authApi,
        _apiClient = apiClient,
        _syncConfig = syncConfig,
        _syncPreferences = syncPreferences,
        _authRepository = authRepository,
        _secureStorage = secureStorage,
        _connectionState = connectionState,
        _employeeCloudSessionCoordinator = employeeCloudSessionCoordinator,
        _syncRecovery = syncRecovery,
        _reconcileForReadiness = reconcileForReadiness;

  final AuthApi _authApi;
  final ApiClient _apiClient;
  final SyncConfig _syncConfig;
  final SharedPreferences _syncPreferences;
  final AuthRepositoryImpl _authRepository;
  final SecureStorage _secureStorage;
  final FulusConnectionState _connectionState;
  final EmployeeCloudSessionCoordinator _employeeCloudSessionCoordinator;
  final CloudSyncRecovery _syncRecovery;
  final Future<void> Function() _reconcileForReadiness;

  Future<bool> bootstrap() async {
    if (_connectionState.isCloudOnboardingInProgress) return false;

    try {
      final session = await _authApi.restoreServerSession(
        supabaseUrl: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );

      if (session == null) {
        // An enabled sync configuration with no durable refresh credential
        // means the credential was actually lost. A transient restore failure
        // must not be turned into a false authentication failure.
        if (_syncConfig.isEnabled) {
          final refreshToken = await _apiClient.secureRefreshToken();
          if (refreshToken == null || refreshToken.isEmpty) {
            _connectionState.markSessionExpired();
          }
        }
        return false;
      }

      _connectionState.markSessionAuthenticated();
      await _connectionState.refresh();

      final knownBusinessId =
          _connectionState.selectedBusinessId ??
          _syncPreferences.getString('fulus_local_cloud_business_id');

      await _employeeCloudSessionCoordinator.refreshExistingAccess(
        force: true,
        businessId: knownBusinessId,
      );
      if (_authRepository.currentUser == null) return false;

      final active = _connectionState.membershipContext?.memberships
              .where((m) => m.status == 'active')
              .toList(growable: false) ??
          const [];

      if (active.isEmpty) return false;

      var selectedBusinessId = _connectionState.selectedBusinessId;
      if (selectedBusinessId == null) {
        if (active.length != 1) return false;
        await _connectionState.selectBusiness(active.single.businessId);
        selectedBusinessId = _connectionState.selectedBusinessId;
      }

      if (selectedBusinessId == null) {
        throw StateError('No active business is available for Cloud Sync.');
      }

      if (knownBusinessId == null) {
        await _employeeCloudSessionCoordinator.refreshExistingAccess(
          force: true,
          businessId: selectedBusinessId,
        );
        if (_authRepository.currentUser == null) return false;
      }

      final package = await PackageInfo.fromPlatform();
      final deviceClientId =
          await _secureStorage.ensureDeviceClientId(Ulid().toString());

      await _connectionState.registerDevice(
        deviceClientId: deviceClientId,
        deviceName: 'Fulus Mobile',
        platform: Platform.operatingSystem,
        appVersion: package.version,
      );

      // The local Drift database is single-business. A business switch
      // therefore requires an authoritative recovery before the new business
      // can be bound to the local cloud dataset.
      const localCloudBusinessKey = 'fulus_local_cloud_business_id';
      final boundBusinessId =
          _syncPreferences.getString(localCloudBusinessKey);

      if (boundBusinessId == null) {
        final persisted = await _syncPreferences.setString(
          localCloudBusinessKey,
          selectedBusinessId,
        );
        if (!persisted) {
          throw StateError(
            'Failed to persist the local Cloud Sync business binding.',
          );
        }
      } else if (boundBusinessId != selectedBusinessId) {
        try {
          await _syncRecovery.recover(businessId: selectedBusinessId);
        } catch (_) {
          // Do not expose business B while the local database still contains
          // business A. Recovery is authoritative; failure rolls selection
          // back and leaves sync blocked.
          await _connectionState.selectBusiness(boundBusinessId);
          rethrow;
        }

        final persisted = await _syncPreferences.setString(
          localCloudBusinessKey,
          selectedBusinessId,
        );
        if (!persisted) {
          throw StateError(
            'Failed to persist the switched Cloud Sync business binding.',
          );
        }
      }

      await _reconcileForReadiness();
      return true;
    } catch (error) {
      rethrow;
    }
  }
}
