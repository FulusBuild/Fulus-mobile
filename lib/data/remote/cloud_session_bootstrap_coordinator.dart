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
import '../local/database/database.dart';
import '../local/sync_cursor_store.dart';
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
    required AppDatabase database,
    required SyncCursorStore syncCursorStore,
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
        _db = database,
        _syncCursorStore = syncCursorStore,
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
  final AppDatabase _db;
  final SyncCursorStore _syncCursorStore;
  final AuthRepositoryImpl _authRepository;
  final SecureStorage _secureStorage;
  final FulusConnectionState _connectionState;
  final EmployeeCloudSessionCoordinator _employeeCloudSessionCoordinator;
  final CloudSyncRecovery _syncRecovery;
  final Future<void> Function() _reconcileForReadiness;

  Future<void> _writeLocalBusinessBinding(String businessId) async {
    await _db.into(_db.localCloudBindings).insertOnConflictUpdate(
      LocalCloudBindingsCompanion.insert(
        id: 'singleton',
        businessId: businessId,
        updatedAt: DateTime.now(),
      ),
    );
    // The blocked-change record is a retry barrier, not an acknowledgement.
    // Once the missing binding has been repaired, permit the same unchanged
    // cursor sequence to be applied again instead of remaining exhausted.
    await _syncCursorStore.clearBlockedChange(businessId);
  }

  Future<bool> bootstrap() async {
    if (_connectionState.isCloudOnboardingInProgress) return false;

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

      // The local Drift database is single-business. The SQLite binding is
      // authoritative; SharedPreferences is the legacy fallback used by
      // releases that predate local_cloud_bindings.
      const localCloudBusinessKey = 'fulus_local_cloud_business_id';
      final preferencesBusinessId =
          _syncPreferences.getString(localCloudBusinessKey);
      final localBinding = await (_db.select(_db.localCloudBindings)
            ..where((row) => row.id.equals('singleton')))
          .getSingleOrNull();
      final boundBusinessId =
          localBinding?.businessId ?? preferencesBusinessId;

      if (boundBusinessId == null) {
        // First binding: this is the same initial-bind decision previously
        // made in preferences, now persisted in SQLite as well so canonical
        // apply has the durable safety fence it requires.
        await _writeLocalBusinessBinding(selectedBusinessId);
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
      } else {
        // Backfill the SQLite binding for devices restored by an older app:
        // those versions wrote the preferences key after restore but omitted
        // the row required by the current canonical-apply transaction.
        if (localBinding == null) {
          await _writeLocalBusinessBinding(selectedBusinessId);
        }
        if (preferencesBusinessId != selectedBusinessId) {
          final persisted = await _syncPreferences.setString(
            localCloudBusinessKey,
            selectedBusinessId,
          );
          if (!persisted) {
            throw StateError(
              'Failed to persist the local Cloud Sync business binding.',
            );
          }
        }
      }

    await _reconcileForReadiness();
    return true;
  }
}
