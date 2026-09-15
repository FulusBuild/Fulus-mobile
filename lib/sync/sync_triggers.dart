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
    Connectivity? connectivity,
  })  : _syncEngine = syncEngine,
        _syncConfig = syncConfig,
        _syncStatusNotifier = syncStatusNotifier,
        _pullFromServer = pullFromServer,
        _isReady = isReady,
        _connectivity = connectivity ?? Connectivity();

  final SyncEngine _syncEngine;
  final SyncConfig _syncConfig;
  final SyncStatusNotifier _syncStatusNotifier;
  final Future<void> Function()? _pullFromServer;
  final Future<bool> Function()? _isReady;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;
  Future<void>? _connectivityRun;

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
    await _runIfOnline();
    if (!_syncConfig.isEnabled || _subscription != null) return;
    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_runIfOnline());
    });
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
    await _runSyncCycle(manual: true);
    await _syncStatusNotifier.checkForStuckSyncAndNotify();
  }

  Future<void> notifyEnqueued() async {
    if (!_syncConfig.isEnabled) return;
    await _runIfOnline();
  }

  Future<void> _runIfOnline() {
    final active = _connectivityRun;
    if (active != null) return active;
    final run = _runIfOnlineOnce();
    _connectivityRun = run;
    return run.whenComplete(() {
      if (identical(_connectivityRun, run)) {
        _connectivityRun = null;
      }
    });
  }

  Future<void> _runIfOnlineOnce() async {
    if (!_syncConfig.isEnabled) return;
    final ready = _isReady;
    if (ready != null && !await ready()) return;
    final results = await _connectivity.checkConnectivity();
    if (_hasConnectivity(results)) {
      // Await the complete cycle. This keeps trigger completion aligned with
      // queue drain + server reconciliation and prevents startup/connectivity
      // races from observing a half-finished sync cycle.
      await _runAndCheckStuck();
    }
  }

  Future<void> _runAndCheckStuck() async {
    await _runSyncCycle();
    await _syncStatusNotifier.checkForStuckSyncAndNotify();
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
