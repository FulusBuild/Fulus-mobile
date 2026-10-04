import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/errors/failure.dart';

import 'sync_engine.dart';
import 'sync_status_notifier.dart';
import 'sync_execution_lease.dart';
import 'sync_cycle_runner.dart';
import 'sync_readiness_gate.dart';
import 'sync_runtime.dart';
import 'sync_readiness_recovery.dart';

/// Adapts platform lifecycle events into the internal synchronization
/// authority. Push/pull cycle policy lives in [SyncCycleRunner].
///
/// [isReady] is deliberately separate from the service-owned persisted
/// switch means "the user enabled sync", while readiness means the current
/// session has an authenticated membership and an active registered device.
/// Keeping those states separate prevents startup/lifecycle triggers from
/// racing device registration after restore or token recovery.
class SyncTriggers with WidgetsBindingObserver implements SyncRuntime {
  SyncTriggers({
    required SyncEngine syncEngine,
    required bool Function() isEnabled,
    required SyncStatusNotifier syncStatusNotifier,
    Future<void> Function()? pullFromServer,
    Future<bool> Function()? isReady,
    Future<void> Function()? onNotReady,
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
        _isReady = isReady,
        _onNotReady = onNotReady,
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
    _readinessGate = SyncReadinessGate(
      isEnabled: _isEnabled,
      isReady: _isReady,
      onNotReady: _onNotReady,
      isRestoreReconciliationInProgress: () =>
          _restoreReconciliationInProgress,
    );
    _readinessRecovery = SyncReadinessRecovery(
      isActive: () => _started && _isEnabled(),
      canRun: () => _syncCycleRun == null && _connectivityRun == null,
      recover: () => _runIfOnline(),
      onFailure: (error, stackTrace) {
        if (_started) _onSyncFailure?.call(error, stackTrace);
      },
    );
  }

  final bool Function() _isEnabled;
  final SyncStatusNotifier _syncStatusNotifier;
  final Future<bool> Function()? _isReady;
  final Future<void> Function()? _onNotReady;
  final void Function()? _onSyncSuccess;
  final void Function(Object error, StackTrace stackTrace)? _onSyncFailure;
  final Future<void> Function()? _onContextChangeReconciled;
  final Connectivity _connectivity;
  late final SyncCycleRunner _cycleRunner;
  late final SyncReadinessGate _readinessGate;
  final Duration retryInterval;
  final Future<void> Function()? _onDeviceAuthorizationLost;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _retryTimer;
  late final SyncReadinessRecovery _readinessRecovery;
  bool _started = false;
  bool _disposed = false;
  Future<bool>? _connectivityRun;
  bool _restoreReconciliationInProgress = false;
  Future<void>? _restoreReconciliationRun;

  /// Arms the restore gate before sync is enabled.
  ///
  /// SyncService enables sync through its persisted configuration listener. Restore must
  /// therefore mark itself as the owner of the initial reconciliation before
  /// flipping that persisted switch, otherwise the normal readiness trigger
  /// can start a competing initialization first.
  void beginRestoreReconciliation() {
    if (_disposed) {
      throw StateError('SyncTriggers has been disposed and cannot begin restore.');
    }
    if (_restoreReconciliationRun != null) {
      throw StateError('A cloud restore reconciliation is already in progress.');
    }
    _restoreReconciliationInProgress = true;
  }

  /// Releases a restore gate that was armed but never reached
  /// [reconcileAfterRestore], for example when local restore setup fails.
  void cancelRestoreReconciliation() {
    if (_restoreReconciliationRun == null) {
      _restoreReconciliationInProgress = false;
    }
  }
  Future<bool>? _syncCycleRun;
  Future<void>? _followUpRun;
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
      final followUp = _followUpRun;
      if (followUp != null) {
        await followUp;
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
SyncFailure?.call(error, stackTrace);
      }
    }
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

  Future<bool> _runIfOnline({bool requireReady = true}) async {
    final active = _connectivityRun;
    if (active != null) {
      return await active;
    }
    final run = _runIfOnlineOnce(requireReady: requireReady);
    _connectivityRun = run;
    try {
      return await run;
    } finally {
      if (identical(_connectivityRun, run)) {
        _connectivityRun = null;
      }
    }
  }

  Future<bool> _runIfOnlineOnce({required bool requireReady}) async {
    if (!_isEnabled()) return false;
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

    // Cycle execution and lease ownership are delegated to SyncCycleRunner.
    // This method retains only same-runtime serialization and follow-up
    // scheduling for mutations committed while the cycle is in flight.
    late Future<bool> run;
    run = _cycleRunner.run(manual: manual);
    _syncCycleRun = run;
    try {
      return await run;
    } finally {
      final followUpRequested = _syncRequestedAfterCycle;
      _syncRequestedAfterCycle = false;
      if (identical(_syncCycleRun, run)) {
        _syncCycleRun = null;
      }
      if (followUpRequested && _isEnabled() && _started) {
        final completer = Completer<void>();
        _followUpRun = completer.future;
        Timer.run(() async {
          try {
            await _runIfOnline();
          } catch (error, stackTrace) {
            if (_started) {
              _onSyncFailure?.call(error, stackTrace);
            }
          } finally {
            if (identical(_followUpRun, completer.future)) {
              _followUpRun = null;
            }
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        });
      }
    }
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}  void scheduleReadinessRecovery() => _readinessRecovery.schedule();


