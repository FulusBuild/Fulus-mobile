import 'dart:async';

/// Owns the restore reconciliation fence used to prevent normal readiness
/// triggers from racing the authoritative post-restore reconciliation.
///
/// The gate contains only lifecycle state. It does not know about sync,
/// connectivity, authentication, or persistence.
class SyncRestoreReconciliationGate {
  bool _inProgress = false;
  Future<void>? _activeRun;

  bool get isInProgress => _inProgress;
  Future<void>? get activeRun => _activeRun;

  void begin() {
    if (_activeRun != null) {
      throw StateError('A cloud restore reconciliation is already in progress.');
    }
    _inProgress = true;
  }

  void cancel() {
    if (_activeRun == null) {
      _inProgress = false;
    }
  }

  Future<void> run(Future<void> Function() reconcile) {
    final active = _activeRun;
    if (active != null) {
      return active;
    }

    // Publish the active reconciliation before invoking the callback. The
    // callback may synchronously re-enter the gate before its first await;
    // re-entry must share the same restore reconciliation.
    final completer = Completer<void>();
    final run = completer.future;
    _activeRun = run;
    // Start the callback in a microtask so the published future is visible
    // before user code can re-enter the gate.
    unawaited(Future.microtask(() => _execute(run, completer, reconcile)));
    return run;
  }

  Future<void> _execute(
    Future<void> run,
    Completer<void> completer,
    Future<void> Function() reconcile,
  ) async {
    _inProgress = true;
    try {
      await reconcile();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _inProgress = false;
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    }
  }

  void dispose() {
    _inProgress = false;
  }
}
