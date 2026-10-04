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

  bool get isEnabled => _config.isEnabled;

  Future<void> enable() => _config.setEnabled(true);

  Future<void> disable() => _config.setEnabled(false);

  Future<void> start() => _triggers.start();

  Future<void> waitForIdle() => _triggers.waitForIdle();

  Future<void> syncNow() => _triggers.syncNow();

  Future<void> refreshAfterContextChange() =>
      _triggers.refreshAfterContextChange();

  Future<void> reconcileAfterRestore() => _triggers.reconcileAfterRestore();

  Future<void> reconcileForReadiness() => _triggers.reconcileForReadiness();

  Future<void> notifyEnqueued() => _triggers.notifyEnqueued();

  void beginRestoreReconciliation() =>
      _triggers.beginRestoreReconciliation();

  void cancelRestoreReconciliation() =>
      _triggers.cancelRestoreReconciliation();

  void scheduleReadinessRecovery() => _triggers.scheduleReadinessRecovery();

  void dispose() => _triggers.dispose();
}
