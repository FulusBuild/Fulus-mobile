import 'package:drift/drift.dart';

import '../../core/errors/failure.dart';
import '../local/database/database.dart';
import 'cloud_restore_api.dart';
import 'cloud_sync_bootstrap_coordinator.dart';

/// Performs the complete cursor-too-old recovery protocol.
///
/// The recovery boundary is deliberately strict: all outbound work must have
/// settled and no unresolved conflict may exist before an authoritative
/// snapshot is allowed to replace cloud-owned local rows. This prevents a
/// stale-cursor recovery from silently destroying legitimate local edits.
class CloudSyncRecovery {
  CloudSyncRecovery({
    required AppDatabase db,
    required CloudRestoreApi restoreApi,
    required CloudSyncBootstrapCoordinator bootstrapCoordinator,
    required Future<void> Function() onStarted,
    required Future<void> Function(int boundary) onCompleted,
    required Future<void> Function(Object error) onFailed,
  })  : _db = db,
        _restoreApi = restoreApi,
        _bootstrapCoordinator = bootstrapCoordinator,
        _onStarted = onStarted,
        _onCompleted = onCompleted,
        _onFailed = onFailed;

  final AppDatabase _db;
  final CloudRestoreApi _restoreApi;
  final CloudSyncBootstrapCoordinator _bootstrapCoordinator;
  final Future<void> Function() _onStarted;
  final Future<void> Function(int boundary) _onCompleted;
  final Future<void> Function(Object error) _onFailed;

  Future<void> recover({required String businessId}) async {
    await _onStarted();
    try {
      final pending = await _db.select(_db.syncQueueItems).get();
      if (pending.isNotEmpty) {
        throw const BusinessRuleFailure(
          'Cloud history is too old, but local changes are still waiting to be sent. Resolve pending sync work before recovery continues.',
          code: 'SYNC_RECOVERY_BLOCKED_PENDING',
        );
      }

      final conflicts = await (_db.select(_db.syncConflictRecords)
            ..where((c) => c.resolvedAt.isNull()))
          .get();
      if (conflicts.isNotEmpty) {
        throw const BusinessRuleFailure(
          'Cloud history is too old while a local conflict still needs review. Resolve the conflict before recovery continues.',
          code: 'SYNC_RECOVERY_BLOCKED_CONFLICT',
        );
      }

      final snapshot = await _restoreApi.fetchSnapshot(businessId: businessId);
      final boundary = await _bootstrapCoordinator.bootstrap(snapshot: snapshot);
      await _onCompleted(boundary);
    } catch (error) {
      await _onFailed(error);
      rethrow;
    }
  }
}
