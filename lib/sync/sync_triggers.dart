import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/errors/failure.dart';

import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_status_notifier.dart';
import 'sync_execution_lease.dart';

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
    Future<void> Function()? onPushSuccess,
    Future<void> Function()? onCursorTooOldRecovery,
    Future<void> Function()? onRecoveryReconciled,
    Future<void> Function(Object error)? onRecoveryFailed,
    void Function(Object error, StackTrace stackTrace)? onSyncFailure,
    Connectivity? connectivity,
    this.retryInterval = const Duration(seconds: 30),
    Future<void> Function()? onDeviceAuthorizationLost,
    SyncExecutionLease? executionLease,
  })  : _syncEngine = syncEngine,
        _syncConfig = syncConfig,
        _syncStatusNotifier = syncStatusNotifier,
        _pullFromServer = pullFromServer,
        _onDeviceAuthorizationLost = onDeviceAuthorizationLost,
        _isReady = isReady,
        _onNotReady = onNotReady,
        _onSyncSuccess = onSyncSuccess,
        _onPushSuccess = onPushSuccess,
        _onCursorTooOldRecovery = onCursorTooOldRecovery,
        _onRecoveryReconciled = onRecoveryReconciled,
        _onRecoveryFailed = onRecoveryFailed,
        _onSyncFailure = onSyncFailure,
        _connectivity = connectivity ?? Connectivity(),
        _executionLease = executionLease;

  final SyncEngine _syncEngine;
  final SyncConfig _syncConfig;
  final SyncStatusNotifier _syncStatusNotifier;
  final Future<void> Function()? _pullFromServer;
  final Future<bool> Function()? _isReady;
  final Future<void> Function()? _onNotReady;
  final void Function()? _onSyncSuccess;
  final Future<void> Function()? _onPushSuccess;
  final Future<void> Function()? _onCursorTooOldRecovery;
  final Future<void> Function()? _onRecoveryReconciled;
  final Future<void> Function(Object error)? _onRecoveryFailed;
  final void Function(Object error, StackTrace stackTrace)? _onSyncFailure;
  final Connectivity _connectivity;
  final SyncExecutionLease? _executionLease;
  final Duration retryInterval;
  final Future<void> Function()? _onDeviceAuthorizationLost;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  Timer? _readinessRecoveryTimer;
  bool _started = false;
  Future<bool>? _connectivityRun;
  Future<void>? _readinessRun;
  bool _restoreReconciliationInProgress = false;
  Future<void>? _restoreReconciliationRun;
  Future<bool>? _syncCycleRun;
  bool _syncRequestedAfterCycle = false;

  /// Waits for any in-flight push/pull/recovery cycle to finish.
  ///
  /// This intentionally does not wait for readiness/connectivity orchestration.
  /// Business switching can itself be invoked by the readiness initializer;
  /// waiting on [_readinessRun] from inside that initializer would deadlock.
  /// The safety property needed here is narrower: do not rebind the single-
  /// business local database while an actual sync/recovery cycle is applying
  /// cloud or outbound state.
  Future<void> waitForIdle() async {
    while (true) {
      final syncCycle = _syncCycleRun;
      if (syncCycle != null) {
        await syncCycle;
        continue;
      }
      final restore = _restoreReconciliationRun;
      if (restore != null) {
        await restore;
        continue;
      }
      return;
    }
  }

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
    _retryTimer ??= Timer.periodic(retryInterval, (_) {
      if (_syncConfig.isEnabled) {
        unawaited(_runIfOnlineSafely());
      }
    });
    // Subscribe before the initial run. If restored-session initialization
    // fails (for example because the device is offline), the connectivity
    // listener remains alive and can retry readiness when connectivity returns.
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_runIfOnlineSafely());
    });
    if (!_syncConfig.isEnabled) return;
    await _runIfOnline();
  }

  void dispose() {
    _syncConfig.removeListener(_onConfigChanged);
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _readinessRecoveryTimer?.cancel();
    _readinessRecoveryTimer = null;
    _started = false;
  }

  void _onConfigChanged() {
    if (_syncConfig.isEnabled) {
      unawaited(_activateSafely());
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _subscription?.cancel();
      _subscription = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      _readinessRecoveryTimer?.cancel();
      _readinessRecoveryTimer = null;
    }
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_syncConfig.isEnabled) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfOnlineSafely());
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
      final initialized = await _ensureReady();
      if (initialized || await ready()) {
        // Readiness initialization owns the first reconciliation. If it
        // completed successfully, there is nothing else to run here.
        if (initialized) return;
      }
      throw StateError(
        'Fulus Cloud is not ready: authentication, business membership, '
        'and active device registration are required before syncing.',
      );
    }
    try {
      final didRun = await _runSyncCycle(manual: true);
      if (!didRun) return;
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
        // A normal trigger may already own the reconciliation. Its result
        // tells restore whether real sync work happened or whether the
        // trigger stood down because restore was still establishing readiness.
        final didReconcile = await active;
        if (didReconcile) return;
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
    // A local mutation can be committed while the push phase is in flight.
    // Do not let that mutation run before the current cycle's pull advances
    // the local cursor; its base cursor may otherwise be stale relative to a
    // successful earlier mutation of the same entity on this device.
    if (_syncCycleRun != null) {
      _syncRequestedAfterCycle = true;
      return;
    }
    await _runIfOnline();
  }

  /// Schedules a readiness recovery after the current sync cycle yields. This
  /// is used when the server revokes this installation's device registration.
  /// The recovery must not run inline from SyncEngine because doing so would
  /// recursively await the cycle that is currently executing.
  void scheduleReadinessRecovery() {
    if (_readinessRecoveryTimer != null) return;
    _readinessRecoveryTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (timer) {
        if (!_started || !_syncConfig.isEnabled) {
          timer.cancel();
          _readinessRecoveryTimer = null;
          return;
        }

        // Device revocation can be detected from inside the active sync
        // cycle. Never await that cycle from inside itself. Poll the lifecycle
        // boundary from a separate timer and start readiness only after both
        // the cycle and its outer connectivity orchestration have unwound.
        if (_syncCycleRun != null || _connectivityRun != null) return;

        timer.cancel();
        _readinessRecoveryTimer = null;
        unawaited(
          _runIfOnline().catchError((Object error, StackTrace stackTrace) {
            if (_started) {
              _onSyncFailure?.call(error, stackTrace);
            }
          }),
        );
      },
    );
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
      return await ready();
    }
    final run = initialize();
    _readinessRun = run;
    try {
      await run;
      // onNotReady owns the initial reconciliation. Only report success
      // when it actually established readiness; initialization may also
      // legitimately return early (for example while offline or signed out).
      return await ready();
    } finally {
      if (identical(_readinessRun, run)) {
        _readinessRun = null;
      }
    }
  }

  Future<void> _activateSafely() async {
    try {
      await _activate();
    } catch (error, stackTrace) {
      if (_started) {
        _onSyncFailure?.call(error, stackTrace);
      }
    }
  }

  Future<void> _runIfOnlineSafely() async {
    try {
      await _runIfOnline();
    } catch (error, stackTrace) {
      if (_started) {
        _onSyncFailure?.call(error, stackTrace);
      }
    }
  }

  Future<void> _runIfOnline({bool requireReady = true}) async {
    final active = _connectivityRun;
    if (active != null) {
      await active;
      return;
    }
    final run = _runIfOnlineOnce(requireReady: requireReady);
    _connectivityRun = run;
    try {
      await run;
    } finally {
      if (identical(_connectivityRun, run)) {
        _connectivityRun = null;
      }
    }
  }

  Future<bool> _runIfOnlineOnce({required bool requireReady}) async {
    if (!_syncConfig.isEnabled) return false;
    if (requireReady) {
      final initialized = await _ensureReady();
      final ready = _isReady;
      if (ready != null && !await ready()) return false;
      if (initialized) return true;
    }
    final results = await _connectivity.checkConnectivity();
    if (!_hasConnectivity(results)) return false;
    await _runAndCheckStuck();
    return true;
  }

  Future<void> _runAndCheckStuck() async {
    try {
      final didRun = await _runSyncCycle();
      if (!didRun) return;
      await _syncStatusNotifier.checkForStuckSyncAndNotify();
      _onSyncSuccess?.call();
    } on AuthFailure catch (error, stackTrace) {
      if (error.requiresDeviceRegistration) {
        await _onDeviceAuthorizationLost?.call();
        return;
      }
      _onSyncFailure?.call(error, stackTrace);
      rethrow;
    } catch (error, stackTrace) {
      _onSyncFailure?.call(error, stackTrace);
      rethrow;
    }
  }

  Future<bool> _runSyncCycle({bool manual = false}) async {
    final active = _syncCycleRun;
    if (active != null) return active;

    final lease = _executionLease;
    if (lease != null && !await lease.acquire()) {
      // Another Fulus runtime owns the durable SQLite sync lease. Treat this
      // wake-up as a no-op and allow a later foreground or WorkManager trigger
      // to run once the active cycle has released the lease.
      return false;
    }

    late Future<bool> run;
    run = () async {
      try {
        await _performSyncCycle(manual: manual);
        return true;
      } finally {
        await lease?.release();
      }
    }();
    _syncCycleRun = run;
    try {
      return await run;
    } finally {
      final followUpRequested = _syncRequestedAfterCycle;
      _syncRequestedAfterCycle = false;
      if (identical(_syncCycleRun, run)) {
        _syncCycleRun = null;
      }
      if (followUpRequested && _syncConfig.isEnabled && _started) {
        // Start only after the active-cycle marker has been cleared so the
        // follow-up cannot recursively await the cycle that requested it.
        Timer.run(() {
          unawaited(
            _runIfOnline().catchError((Object error, StackTrace stackTrace) {
              if (_started) {
                _onSyncFailure?.call(error, stackTrace);
              }
            }),
          );
        });
      }
    }
  }

  Future<void> _performSyncCycle({bool manual = false}) async {
    await _syncEngine.runOnce(manual: manual);
    await _onPushSuccess?.call();
    final pull = _pullFromServer;
    if (pull != null) {
      // Pull failures are intentionally propagated. A reconciliation failure
      // is a real sync failure and must remain observable to the caller and
      // diagnostic layer rather than being silently converted into success.
      var recoveredFromStaleCursor = false;
      try {
        await pull();
      } on BusinessRuleFailure catch (error) {
        if (error.code != 'SYNC_CURSOR_TOO_OLD') rethrow;
        final recover = _onCursorTooOldRecovery;
        if (recover == null) rethrow;
        await recover();
        recoveredFromStaleCursor = true;
        try {
          await pull();
        } catch (error) {
          await _onRecoveryFailed?.call(error);
          rethrow;
        }
      }
      // Recovery deliberately clears Sync Ready while bootstrap replaces local
      // cloud-owned state. Readiness is restored only after the post-bootstrap
      // delta pull succeeds, so the UI can never advertise readiness before
      // authoritative reconciliation has completed.
      if (recoveredFromStaleCursor) {
        try {
          await _onRecoveryReconciled?.call();
        } catch (error) {
          await _onRecoveryFailed?.call(error);
          rethrow;
        }
      }
    }
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}