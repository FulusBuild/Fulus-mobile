import 'dart:async';

import 'sync_config.dart';
import 'sync_runtime.dart';

enum SyncReadinessState {
  notReady,
  bootstrapping,
  ready,
  error,
}

/// Single public synchronization boundary for the application.
///
/// Application callers depend only on this service. The concrete runtime is
/// an internal adapter over the proven sync engine and trigger machinery.
///
/// This is intentionally a facade-first refactor: the durable outbox,
/// idempotency, leases, cursor safety, reconciliation and retry machinery are
/// preserved while lifecycle ownership is consolidated behind one boundary.
class SyncService {
  SyncService(
    this._runtime,
    this._config, {
    Future<bool> Function()? bootstrapCloud,
    void Function(SyncReadinessState state, Object? error)? onReadinessChanged,
  }) : _bootstrapCloud = bootstrapCloud,
       _onReadinessChanged = onReadinessChanged;

  final SyncRuntime _runtime;
  final SyncConfig _config;
  final Future<bool> Function()? _bootstrapCloud;
  final void Function(SyncReadinessState state, Object? error)? _onReadinessChanged;
  SyncReadinessState _readinessState = SyncReadinessState.notReady;
  Object? _readinessError;
  bool _started = false;
  bool _restoreGateArmed = false;
  bool _disposed = false;
  Future<void>? _runtimeStart;
  Future<void>? _cloudBootstrapRun;

  bool get isEnabled => _config.isEnabled;
  SyncReadinessState get readinessState => _readinessState;
  bool get isReady => _readinessState == SyncReadinessState.ready;
  Object? get readinessError => _readinessError;

  Future<void> enable() {
    _ensureActive();
    return _enableAndStartIfActive();
  }

  Future<void> disable() async {
    _ensureActive();
    await _config.setEnabled(false);
    markNotReady();
    if (_started) _runtime.stop();
  }

  Future<void> _enableAndStartIfActive() async {
    await _config.setEnabled(true);
    if (_started && !_restoreGateArmed) {
      await _startRuntime();
    }
  }

  /// Enables sync while reserving the first reconciliation for an explicit
  /// restore completion. The reservation belongs to the public lifecycle
  /// authority; the runtime only receives the compatibility gate operation.
  Future<void> enableForRestore() async {
    _ensureActive();
    if (_restoreGateArmed) {
      throw StateError('A cloud restore reconciliation is already reserved.');
    }
    _restoreGateArmed = true;
    try {
      _runtime.beginRestoreReconciliation();
      await _config.setEnabled(true);
    } catch (_) {
      _restoreGateArmed = false;
      _runtime.cancelRestoreReconciliation();
      rethrow;
    }
  }

  /// Cancels a restore reservation when restore setup fails before the
  /// authoritative post-restore reconciliation can run.
  void cancelRestore() {
    if (!_restoreGateArmed) return;
    _restoreGateArmed = false;
    _runtime.cancelRestoreReconciliation();
  }

  /// Starts the synchronization lifecycle for the current application
  /// runtime. This is the only application-facing startup operation.
  /// Owns the semantic cloud-readiness bootstrap entry point.
  ///
  /// The concrete cloud session/business/device bootstrap is composed by the
  /// application root, but lifecycle/readiness triggers may enter it only
  /// through this service boundary. This keeps SyncTriggers as an event
  /// adapter rather than a second application-facing bootstrap authority.
  Future<void> bootstrapCloud() {
    _ensureActive();
    final active = _cloudBootstrapRun;
    if (active != null) return active;

    final run = _runCloudBootstrap();
    _cloudBootstrapRun = run;
    return run.whenComplete(() {
      if (identical(_cloudBootstrapRun, run)) {
        _cloudBootstrapRun = null;
      }
    });
  }

  Future<void> _runCloudBootstrap() async {
    final bootstrapCloud = _bootstrapCloud;
    if (bootstrapCloud == null) {
      throw StateError('Cloud bootstrap is not configured.');
    }

    _setReadiness(SyncReadinessState.bootstrapping);
    try {
      final ready = await bootstrapCloud();
      if (ready) {
        markReady();
      } else {
        markNotReady();
      }
    } catch (error) {
      markReadinessError(error);
      rethrow;
    }
  }

  /// Records that the cloud lifecycle has completed its authoritative
  /// readiness boundary. Only SyncService owns this state; connection state
  /// receives the resulting projection through [onReadinessChanged].
  void markReady() {
    _ensureActive();
    _setReadiness(SyncReadinessState.ready);
  }

  void markNotReady() {
    if (_disposed) return;
    _setReadiness(SyncReadinessState.notReady);
  }

  void markReadinessError(Object error) {
    if (_disposed) return;
    _setReadiness(SyncReadinessState.error, error);
  }

  void _setReadiness(SyncReadinessState state, [Object? error]) {
    if (_readinessState == state && identical(_readinessError, error)) return;
    _readinessState = state;
    _readinessError = error;
    _onReadinessChanged?.call(state, error);
  }

  Future<void> bootstrap() async {
    if (_disposed) {
      throw StateError('SyncService has been disposed and cannot bootstrap.');
    }
    if (_started) return;
    _started = true;
    _config.addListener(_onConfigChanged);
    try {
      if (_config.isEnabled && !_restoreGateArmed) {
        await _startRuntime();
      }
    } catch (_) {
      _config.removeListener(_onConfigChanged);
      _started = false;
      rethrow;
    }
  }

  void _onConfigChanged() {
    if (_config.isEnabled) {
      if (_restoreGateArmed) return;
      unawaited(
        _startRuntime().catchError((error, stackTrace) {
          // SyncConfig is intentionally a persisted setting, but it remains
          // a ChangeNotifier for non-sync infrastructure such as WorkManager.
          // If a legacy/external writer changes it outside enable(), keep the
          // failure inside the SyncService boundary instead of creating an
          // unhandled future from a fire-and-forget lifecycle callback.
          markReadinessError(error);
          return Future<void>.value();
        }),
      );
    } else {
      markNotReady();
      _runtime.stop();
    }
  }

  Future<void> _startRuntime() {
    final active = _runtimeStart;
    if (active != null) return active;
    final run = _runtime.start();
    _runtimeStart = run;
    return run.whenComplete(() {
      if (identical(_runtimeStart, run)) {
        _runtimeStart = null;
      }
    });
  }

  /// Requests an immediate synchronization cycle.
  Future<void> request() {
    _ensureActive();
    if (!_config.isEnabled) return Future<void>.value();
    return _runtime.request();
  }

  Future<void> waitForIdle() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _runtime.waitForIdle();
  }

  Future<void> refreshAfterContextChange() {
    _ensureActive();
    return _runtime.refreshAfterContextChange();
  }

  Future<void> reconcileAfterRestore() async {
    _ensureActive();
    if (!_restoreGateArmed) {
      throw StateError(
        'reconcileAfterRestore() requires an active restore reservation.',
      );
    }
    try {
      await _runtime.reconcileAfterRestore();
    } finally {
      _restoreGateArmed = false;
      // The restore reservation intentionally suppresses the normal lifecycle
      // start while the authoritative snapshot is being reconciled. Re-arm
      // the ordinary runtime only after that boundary has settled, including
      // the failure case so connectivity/retry can recover it.
      if (_started && _config.isEnabled) {
        unawaited(_startRuntime());
      }
    }
  }

  Future<void> reconcileForReadiness() {
    _ensureActive();
    return _runtime.reconcileForReadiness();
  }

  /// Notifies the synchronization authority that a durable local mutation
  /// has been committed. The queue remains responsible for durability; this
  /// callback only wakes the existing sync runtime after the transaction has
  /// committed.
  Future<void> onLocalMutationCommitted() {
    _ensureActive();
    return _runtime.onLocalMutationCommitted();
  }

  /// Requests readiness recovery after the cloud device/session authority is
  /// lost. Recovery scheduling remains an internal runtime concern.
  void recoverReadiness() {
    if (_disposed) return;
    _runtime.recoverReadiness();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('SyncService has been disposed.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_started) {
      _config.removeListener(_onConfigChanged);
      _started = false;
    }
    _restoreGateArmed = false;
    _setReadiness(SyncReadinessState.notReady);
    _runtime.dispose();
  }
}
