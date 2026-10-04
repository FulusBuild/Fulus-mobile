import 'dart:async';

import 'sync_config.dart';
import 'sync_triggers.dart';

/// Single public synchronization boundary for the application.
///
/// The implementation intentionally delegates to the existing trigger/engine
/// stack during the migration. Callers depend on this contract instead of
/// knowing about SyncTriggers, leases, cursors, retries, or reconciliation.
///
/// This is a facade-first refactor: behavior stays unchanged while lifecycle
/// ownership is progressively moved behind one boundary.
class SyncService {
  SyncService(this._triggers, this._config);

  final SyncTriggers _triggers;
  final SyncConfig _config;
  bool _started = false;

  bool get isEnabled => _config.isEnabled;

  Future<void> enable() => _config.setEnabled(true);

  Future<void> disable() => _config.setEnabled(false);

  /// Enables sync while reserving the first reconciliation for an explicit
  /// restore completion. This keeps the restore race protection inside the
  /// synchronization boundary instead of exposing trigger-specific fencing
  /// to the UI.
  Future<void> enableForRestore() async {
    _triggers.beginRestoreReconciliation();
    try {
      await _config.setEnabled(true);
    } catch (_) {
      _triggers.cancelRestoreReconciliation();
      rethrow;
    }
  }

  /// Cancels a restore reconciliation reservation when restore setup fails
  /// before the authoritative post-restore reconciliation can run.
  void cancelRestore() => _triggers.cancelRestoreReconciliation();

  /// Starts the synchronization lifecycle for the current application runtime.
  ///
  /// Callers should use this bootstrap boundary rather than knowing about
  /// SyncTriggers or its lifecycle observer implementation.
  Future<void> bootstrap() async {
    if (_started) return;
    _started = true;
    _config.addListener(_onConfigChanged);
    if (_config.isEnabled) {
      await _triggers.start();
    }
  }

  void _onConfigChanged() {
    if (_config.isEnabled) {
      unawaited(_triggers.start());
    } else {
      _triggers.stop();
    }
  }

  /// Requests an immediate synchronization cycle.
  ///
  /// This is the single public request boundary. Background, connectivity,
  /// lifecycle, and queue events may all converge on the same underlying
  /// engine; callers do not need to choose a trigger implementation.
  Future<void> request() => _triggers.syncNow();

  Future<void> waitForIdle() => _triggers.waitForIdle();

  Future<void> refreshAfterContextChange() =>
      _triggers.refreshAfterContextChange();

  Future<void> reconcileAfterRestore() => _triggers.reconcileAfterRestore();

  Future<void> reconcileForReadiness() => _triggers.reconcileForReadiness();

  Future<void> notifyEnqueued() => _triggers.notifyEnqueued();

  void beginRestoreReconciliation() =>
      _triggers.beginRestoreReconciliation();

  void cancelRestoreReconciliation() =>
      _triggers.cancelRestoreReconciliation();

  /// Schedules recovery after the cloud device/session authority is lost.\n  /// This is intentionally exposed as a lifecycle operation, not a trigger API.\n  void scheduleReadinessRecovery() => _triggers.scheduleReadinessRecovery();

  void dispose() {
    if (_started) {
      _config.removeListener(_onConfigChanged);
      _started = false;
    }
    _triggers.dispose();
  }
}
