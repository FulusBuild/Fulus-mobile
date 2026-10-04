import 'dart:async';

/// Internal readiness gate used by the sync lifecycle adapter.
///
/// It serializes readiness initialization and keeps authentication/device
/// readiness separate from the persisted sync-enabled setting. The actual
/// bootstrap operation remains supplied by the service/bootstrap boundary.
/// A readiness attempt is shared by concurrent triggers so only one bootstrap
/// operation can initialize the current session at a time.
class SyncReadinessGate {
  SyncReadinessGate({
    required bool Function() isEnabled,
    required Future<bool> Function()? isReady,
    required Future<void> Function()? onNotReady,
    required bool Function() isRestoreReconciliationInProgress,
  })  : _isEnabled = isEnabled,
        _isReady = isReady,
        _onNotReady = onNotReady,
        _isRestoreReconciliationInProgress =
            isRestoreReconciliationInProgress;

  final bool Function() _isEnabled;
  final Future<bool> Function()? _isReady;
  final Future<void> Function()? _onNotReady;
  final bool Function() _isRestoreReconciliationInProgress;
  Future<void>? _initializationRun;

  Future<bool> ensureReady() async {
    if (!_isEnabled()) return false;

    // Restore owns the first reconciliation. A normal trigger that happens
    // to fire while restore is enabling sync must stand down.
    if (_isRestoreReconciliationInProgress()) return false;

    final ready = _isReady;
    if (ready == null || await ready()) return false;

    final initialize = _onNotReady;
    if (initialize == null) return false;

    final active = _initializationRun;
    if (active != null) {
      await active;
      return await ready();
    }

    // Publish the initialization future before invoking the callback. The
    // callback may synchronously re-enter readiness before its first await;
    // re-entry must share the same initialization attempt.
    final completer = Completer<void>();
    final run = completer.future;
    _initializationRun = run;
    unawaited(_executeInitialization(run, completer, initialize));
    await run;
    // Initialization may legitimately return without establishing
    // readiness, for example while offline or signed out.
    return await ready();
  }
}
