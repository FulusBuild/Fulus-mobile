import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/errors/failure.dart';

import 'sync_engine.dart';
import 'sync_status_notifier.dart';
import 'sync_execution_lease.dart';
import 'sync_cycle_runner.dart';
import 'sync_cycle_execution_gate.dart';
import 'sync_connectivity_run_gate.dart';
import 'sync_runtime.dart';
import 'sync_readiness_recovery.dart';
import 'sync_restore_reconciliation_gate.dart';

/// Adapts platform lifecycle events into the internal synchronization
/// authority. Push/pull cycle policy lives in [SyncCycleRunner].
///
/// Readiness is owned by [SyncService]. This runtime adapter only asks the
/// lifecycle authority to establish readiness when a trigger needs it.
class SyncTriggers with WidgetsBindingObserver implements SyncRuntime {
  SyncTriggers({
    required SyncEngine syncEngine,
    required bool Function() isEnabled,
    required SyncStatusNotifier syncStatusNotifier,
    Future<void> Function()? pullFromServer,
    Future<SyncReadinessEnsureResult> Function()? ensureReady,
    void Function()? onSyncSuccess,
    Future<void> Function(bool hadOutboundWork)? onPushSuccess,
    Future<bool> Function()? hasOutboundWork,
    Future<void> Function()? onCursorTooOldRecovery,
    Future<void> Function()? onRecoveryReconciled,
    Future<void> Function(Object error)? onRecoveryFailed,
    void Function(Object error, StackTrace stackTrace)? onSyncFailure,
    Future<void> Function()? onBeforeSyncCycle,
    Future<void> Function()? onContextChangeReconciled,
    Connectivity? connectivity,
    this.retryInterval = const Duration(seconds: 30),
    Future<void> Function()? onDeviceAuthorizationLost,
    SyncExecutionLease? executionLease,
})  : _isEnabled = isEnabled,
        _syncStatusNotifier = syncStatusNotifier,
        _ensureReadyCallback = ensureReady ??
            (() async => SyncReadinessEnsureResult.alreadyReady),
        _onSyncSuccess = onSyncSuccess,
        _onSyncFailure = onSyncFailure,
        _onContextChangeReconciled = onContextChangeReconciled,
        _connectivity = connectivity ?? Connectivity(),
        _onDeviceAuthorizationLost = onDeviceAuthorizationLost {
    _cycleRunner = SyncCycleRunner(
      syncEngine: syncEngine,
      executionLease: executionLease ?? SyncExecutionLease(syncEngine.db),
      hasOutboundWork: hasOutboundWork,
      onPushSuccess: onPushSuccess,
      pullFromServer: pullFromServer,
      onCursorTooOldRecovery: onCursorTooOldRecovery,
      onRecoveryReconciled: onRecoveryReconciled,
      onRecoveryFailed: onRecoveryFailed,
      onBeforeSyncCycle: onBeforeSyncCycle,
    );
    _connectivityGate = SyncConnectivityRunGate(
      run: () => _runIfOnlineOnce(requireReady: true),
    );
    _readinessRecovery = SyncReadinessRecovery(
      isActive: () => _started && _isEnabled(),
      canRun: () => !_cycleExecutionGate.isRunning && !_connectivityGate.isRunning,
      recover: () => _runIfOnline(),
      onFailure: (error, stackTrace) {
        if (_started) _onSyncFailure?.call(error, stackTrace);
      },
    );
    _cycleExecutionGate = SyncCycleExecutionGate(
      runCycle: ({manual = false}) => _cycleRunner.run(manual: manual),
      runFollowUp: _runIfOnline,
      isActive: () => _started && _isEnabled(),
      onFollowUpError: (error, stackTrace) {
        if (_started) _onSyncFailure?.call(error, stackTrace);
      },
    );
  }

  final bool Function() _isEnabled;
  final SyncStatusNotifier _syncStatusNotifier;
  final Future<SyncReadinessEnsureResult> Function()? _ensureReadyCallback;
  final void Function()? _onSyncSuccess;
  final void Function(Object error, StackTrace stackTrace)? _onSyncFailure;
  final Future<void> Function()? _onContextChangeReconciled;
  final Connectivity _connectivity;
  late final SyncCycleRunner _cycleRunner;
  late final SyncCycleExecutionGate _cycleExecutionGate;
  final Duration retryInterval;
  final Future<void> Function()? _onDeviceAuthorizationLost;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  late final SyncReadinessRecovery _readinessRecovery;
  bool _started = false;
  bool _disposed = false;
  late final SyncConnectivityRunGate _connectivityGate;
  final SyncRestoreReconciliationGate _restoreGate =
      SyncRestoreReconciliationGate();

  /// Arms the restore gate before sync is enabled.
  void beginRestoreReconciliation() {
    if (_disposed) {
      throw StateError('SyncTriggers has been disposed and cannot begin restore.');
    }
    _restoreGate.begin();
  }

  /// Releases a restore gate that was armed but never reached
  /// [reconcileAfterRestore], for example when local restore setup fails.
  void cancelRestoreReconciliation() => _restoreGate.cancel();

  /// Waits for any in-flight push/pull/recovery cycle to finish.
  ///
  /// This intentionally does not wait for readiness/connectivity orchestration.
  /// Business switching can itself be invoked by the readiness initializer;
  /// waiting on readiness from inside that initializer would deadlock.
  /// The safety property needed here is narrower: do not rebind the single-
  /// business local database while an actual sync/recovery cycle is applying
  /// cloud or outbound state.
  Future<void> waitForIdle() async {
    while (true) {
      await _cycleExecutionGate.waitForIdle();
      final restore = _restoreGate.activeRun;
      if (restore != null) {
        await restore;
        continue;
      }
      return;
    }
  }

  Future<void> start() async {
    if (_disposed || _started || !_isEnabled()) return;
    _started = true;
    await _activate();
  }

  Future<void> _activate() async {
    if (_subscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _retryTimer ??= Timer.periodic(retryInterval, (_) {
      if (_isEnabled()) {
        unawaited(_runIfOnlineSafely());
      }
    });
    // Subscribe before the initial run. If restored-session initialization
    // fails (for example because the device is offline), the connectivity
    // listener remains alive and can retry readiness when connectivity returns.
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_runIfOnlineSafely());
    });
    if (!_isEnabled()) return;
    await _runIfOnline();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _readinessRecovery.dispose();
    _started = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_isEnabled()) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfOnlineSafely());
    }
  }

  /// Reconcile cloud-owned projections after a business-context switch.
  ///
  /// Switching itself remains local-first and offline-safe. If sync is enabled,
  /// this starts the normal connectivity-gated cycle; when offline, the regular
  /// connectivity/lifecycle triggers will retry without making the switch fail.
  Future<void> refreshAfterContextChange() async {
    if (_disposed || !_isEnabled()) return;
    final didRun = await _runIfOnlineSafely();
    if (!didRun || !_isEnabled()) return;
    await _onContextChangeReconciled?.call();
  }

  Future<void> request() => syncNow();

  Future<void> onLocalMutationCommitted() => notifyEnqueued();

  void recoverReadiness() => scheduleReadinessRecovery();

  Future<void> syncNow() async {
    if (_disposed) {
      throw StateError('SyncTriggers has been disposed and cannot sync.');
    }
    if (!_isEnabled()) {
      throw StateError(
        'SyncTriggers.syncNow() was called while sync is disabled. '
        'Callers should only expose a "Sync Now" action when '
        'SyncStatusNotifier reports sync as enabled.',
      );
    }
    final readiness = await _ensureReady();
    if (readiness == SyncReadinessEnsureResult.initialized) {
      // The readiness bootstrap owns its first reconciliation. Do not run a
      // second sync cycle immediately after it.
      return;
    }
    if (readiness == SyncReadinessEnsureResult.notReady) {
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
    if (_disposed) {
      throw StateError('SyncTriggers has been disposed and cannot reconcile.');
    }
    if (!_isEnabled()) {
      throw StateError(
        'Cannot reconcile a restored business while sync is disabled.',
      );
    }

    await _restoreGate.run(_reconcileAfterRestore);
  }

  Future<void> _reconcileAfterRestore() async {
      final results = await _connectivity.checkConnectivity();
      if (!_hasConnectivity(results)) {
        throw StateError(
          'Fulus Cloud initial reconciliation requires an internet connection.',
        );
      }

      // A normal trigger may already own the connectivity cycle. Waiting
      // for the shared gate preserves the existing serialization boundary.
      if (_connectivityGate.isRunning) {
        final didRun = await _connectivityGate.run();
        if (didRun) return;
      }

      // A connectivity-gated readiness attempt can finish without running a
      // sync cycle (for example, when readiness was blocked and then yielded
      // without establishing readiness). Restore still owns the authoritative
      // first reconciliation, so perform that cycle here rather than treating
      // the readiness attempt itself as the restore reconciliation.
      await _runAndCheckStuck();
  }

  /// Performs the readiness reconciliation after SyncService has established
  /// the cloud session/device context. SyncService owns the lifecycle decision;
  /// this runtime only performs the connectivity-gated reconciliation.
  Future<void> reconcileForReadiness() async {
    if (!_isEnabled()) {
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
    if (_disposed || !_isEnabled()) return;
    // A local mutation can be committed while the push phase is in flight.
    // Do not let that mutation run before the current cycle's pull advances
    // the local cursor; its base cursor may otherwise be stale relative to a
    // successful earlier mutation of the same entity on this device.
    if (_cycleExecutionGate.isRunning) {
      _cycleExecutionGate.requestAfterCurrentCycle();
      return;
    }
    await _runIfOnline();
  }

  /// Schedules a readiness recovery after the current sync cycle yields. This
  /// is used when the server revokes this installation's device registration.
  /// The recovery must not run inline from SyncEngine because doing so would
  /// recursively await the cycle that is currently executing.
  void scheduleReadinessRecovery() => _readinessRecovery.schedule();

  Future<SyncReadinessEnsureResult> _ensureReady() async {
    if (!_isEnabled()) return SyncReadinessEnsureResult.notReady;
    if (_restoreGate.isInProgress) return SyncReadinessEnsureResult.notReady;

    final ensureReady = _ensureReadyCallback;
    if (ensureReady == null) return SyncReadinessEnsureResult.notReady;

    return ensureReady();
  }

  Future<bool> _runIfOnlineSafely() async {
    try {
      return await _runIfOnline();
    } catch (error, stackTrace) {
      if (_started) {
        _onSyncFailure?.call(error, stackTrace);
      }
      return false;
    }
  }

  Future<bool> _runIfOnline() async {
    return _connectivityGate.run();
  }

  Future<bool> _runIfOnlineOnce({required bool requireReady}) async {
    if (!_isEnabled()) return false;
    if (requireReady) {
      final readiness = await _ensureReady();
      if (readiness == SyncReadinessEnsureResult.notReady) return false;
      if (readiness == SyncReadinessEnsureResult.initialized) return true;
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

  Future<bool> _runSyncCycle({bool manual = false}) =>
      _cycleExecutionGate.run(manual: manual);

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
