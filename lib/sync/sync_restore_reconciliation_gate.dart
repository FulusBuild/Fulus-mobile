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

  Future<void> run(Future<void> Function() reconcile) async {
    final active = _activeRun;
    if (active != null) {
      await active;
      return;
    }

    // Publish the active reconciliation before invoking the callback. The
    // callback may synchronously re-enter the gate before its first await;
    // re-entry must share the same restore reconciliation.
    final completer = Completer<void>();
    final run = completer.future;
    _activeRun = run;
    unawaited(_execute(run, completer, reconcile));
    await run
  }

  Future<void> _run(Future<void> Function() reconcile) async {
    _inProgress = true;
    try {
      await reconcile();
    } finally {
      _inProgress = false;
    }
  }

  void dispose() {
    _inProgress = false;
  }
}
