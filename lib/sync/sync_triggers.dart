import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_status_notifier.dart';

/// Wires Architecture Section 8's trigger conditions to SyncEngine.runOnce.
/// Server -> device reconciliation is supplied separately through
/// [pullFromServer] so the queue algorithm remains platform-independent.
///
/// [isReady] is deliberately separate from [SyncConfig]: the persisted
/// switch means "the user enabled sync", while readiness means the current
/// session has an authenticated membership and an active registered device.
/// Keeping those states separate prevents startup/lifecycle triggers from
/// racing device registration after restore or token recovery.
class SyncTriggers with WidgetsBindingObserver {
  SyncTriggers({
    required SyncEngine syncEngine,
    required SyncConfig syncConfig,
    required SyncStatusNotifier syncStatusNotifier,
    Future<void> Function()? pullFromServer,
    Future<bool> Function()? isReady,
    Future<void> Function()? onNotReady,
    void Function()? onSyncSuccess,
    void Function(Object error, StackTrace stackTrace)? onSyncFailure,
    Connectivity? connectivity,
  })  : _syncEngine = syncEngine,
        _syncConfig = syncConfig,
        _syncStatusNotifier = syncStatusNotifier,
        _pullFromServer = pullFromServer,
        _isReady = isReady,
        _onNotReady = onNotReady,
        _onSyncSuccess = onSyncSuccess,
        _onSyncFailure = onSyncFailure,
        _connectivity = connectivity ?? Connectivity();

  final SyncEngine _syncEngine;
  final SyncConfig _syncConfig;
  final SyncStatusNotifier _syncStatusNotifier;
  final Future<void> Function()? _pullFromServer;
  final Future<bool> Function()? _isReady;
  final Future<void> Function()? _onNotReady;
  final void Function()? _onSyncSuccess;
  final void Function(Object error, StackTrace stackTrace)? _onSyncFailure;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;
  Future<void>? _connectivityRun;
  Future<void>? _readinessRun;
  bool _restoreReconciliationInProgress = false;
  Future<void>? _restoreReconciliationRun;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _syncConfig.addListener(_onConfigChanged);
    if (!_syncConfig.isEnabled) return;
    await _activate();
  }

  Future<void> _activate() async {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    // Subscribe before the initial run. If restored-session initialization
    // fails (for example because the device is offline), the connectivity
    // listener remains alive and can retry readiness when connectivity returns.
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_runIfOnline());
    });
    if (!_syncConfig.isEnabled) return;
    await _runIfOnline();
  }

  void dispose() {
    _syncConfig.removeListener(_onConfigChanged);
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }

  void _onConfigChanged() {
    if (_syncConfig.isEnabled) {
      unawaited(_activate());
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_syncConfig.isEnabled) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfOnline());
    }
  }

  Future<void> syncNow() async {
    if (!_syncConfig.isEnabled) {
      throw StateError(
        'SyncTriggers.syncNow() was called while sync is disabled. '
        'Callers should only expose a "Sync Now" action when '
        'SyncStatusNotifier reports sync as enabled.',
      );
    }
    final ready = _isReady;
    if (ready != null && !await ready()) {
      throw StateError(
        'Fulus Cloud is not ready: authentication, business membership, '
        'and active device registration are required before syncing.',
      );
    }
    try {
      await _runSyncCycle(manual: true);
      await _syncStatusNotifier.checkForStuckSyncAndNotify();
      _onSyncSuccess?.call();
    } catch (error, stackTrace) {
      _onSyncFailure?.call(error, stackTrace);
      rethrow;
    }
  }

  /// Runs the first reconciliation after a restore before the connection is
  /// advertised as Sync Ready. Device registration and authentication are
  /// already complete at this point, but readiness is deliberately not used
  /// as a precondition because this call is what establishes readiness.
  ///
  /// Connectivity is checked here because restore is a one-time readiness
  /// gate. The check is intentionally performed only once; normal trigger
  /// paths may use [_runIfOnline], but restore must not accidentally perform
  /// two network-state checks around the same reconciliation.
  Future<void> reconcileAfterRestore() async {
    if (!_syncConfig.isEnabled) {
      throw StateError(
        'Cannot reconcile a restored business while sync is disabled.',
      );
    }

    final activeRestore = _restoreReconciliationRun;
    if (activeRestore != null) {
      await activeRestore;
      return;
    }

    final run = _reconcileAfterRestore();
    _restoreReconciliationRun = run;
    try {
      await run;
    } finally {
      if (identical(_restoreReconciliationRun, run)) {
        _restoreReconciliationRun = null;
      }
    }
  }

  Future<void> _reconcileAfterRestore() async {
    _restoreReconciliationInProgress = true;
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_hasConnectivity(results)) {
        throw StateError(
          'Fulus Cloud initial reconciliation requires an internet connection.',
        );
      }

      // A normal trigger may already own the connectivity cycle. It is safe
      // to wait for that cycle unless it is waiting on this restore through
      // onNotReady. Bootstrap readiness initialization uses
      // reconcileForReadiness() instead, so it never creates that cycle.
      final active = _connectivityRun;
      if (active != null) {
        await active;
        return;
      }

      await _runAndCheckStuck();
    } finally {
      _restoreReconciliationInProgress = false;
    }
  }

  /// Performs the readiness reconciliation without waiting on any normal
  /// trigger or readiness future. This is used by bootstrap's onNotReady hook
  /// and therefore must never call reconcileAfterRestore() or await
  /// _connectivityRun/_readinessRun.
  Future<void> reconcileForReadiness() async {
    if (!_syncConfig.isEnabled) {
      throw StateError(
        'Cannot reconcile for readiness while sync is disabled.',
      );
    }

    final results = await _connectivity.checkConnectivity();
    if (!_hasConnectivity(results)) {
      throw StateError(
        'Fulus Cloud initial reconciliation requires an internet connection.',
      );
    }

    await _runAndCheckStuck();
  }

  Future<void> notifyEnqueued() async {
    if (!_syncConfig.isEnabled) return;
    await _runIfOnline();
  }

  Future<bool> _ensureReady() async {
    // Restore owns the initial reconciliation. A normal trigger that happens
    // to fire while restore is enabling sync must stand down.
    if (_restoreReconciliationInProgress) return false;

    final ready = _isReady;
    if (ready == null || await ready()) return false;
    final initialize = _onNotReady;
    if (initialize == null) return false;
    final active = _readinessRun;
    if (active != null) {
      await active;
      return true;
    }
    final run = initialize();
    _readinessRun = run;
    try {
      await run;
      // onNotReady owns the initial reconciliation. The caller must not run
      // another queue/pull cycle immediately after it completes.
      return true;
    } finally {
      if (identical(_readinessRun, run)) {
        _readinessRun = null;
      }
    }
  }

  Future<void> _runIfOnline({bool requireReady = true}) {
    final active = _connectivityRun;
    if (active != null) return active;
    final run = _runIfOnlineOnce(requireReady: requireReady);
    _connectivityRun = run;
    return run.whenComplete(() {
      if (identical(_connectivityRun, run)) {
        _connectivityRun = null;
      }
    });
  }

  Future<void> _runIfOnlineOnce({required bool requireReady}) async {
    if (!_syncConfig.isEnabled) return;
    if (requireReady) {
      final initialized = await _ensureReady();
      final ready = _isReady;
      if (ready != null && !await ready()) return;
      if (initialized) return;
    }
    final results = await _connectivity.checkConnectivity();
    if (_hasConnectivity(results)) {
      await _runAndCheckStuck();
    }
  }

  Future<void> _runAndCheckStuck() async {
    try {
      await _runSyncCycle();
      await _syncStatusNotifier.checkForStuckSyncAndNotify();
      _onSyncSuccess?.call();
    } catch (error, stackTrace) {
      _onSyncFailure?.call(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _runSyncCycle({bool manual = false}) async {
    await _syncEngine.runOnce(manual: manual);
    final pull = _pullFromServer;
    if (pull != null) {
      // Pull failures are intentionally propagated. A reconciliation failure
      // is a real sync failure and must remain observable to the caller and
      // diagnostic layer rather than being silently converted into success.
      await pull();
    }
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}