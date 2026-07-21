import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_engine.dart';

/// Wires Architecture Section 8's trigger conditions to
/// SyncEngine.runOnce. Deliberately kept separate from sync_engine.dart
/// — that class stays pure Dart with zero Flutter/platform-plugin
/// imports so the queue-draining algorithm itself stays fully unit-
/// testable; this class owns everything that actually depends on
/// Flutter (WidgetsBindingObserver) and a platform plugin
/// (connectivity_plus), and is not itself unit-tested the same way —
/// verified by careful reading against connectivity_plus 6.0.4's actual
/// documented API instead (see the two version-specific facts noted
/// below).
///
/// What this class does NOT cover: WorkManager-scheduled background
/// sync (Section 8's fourth mechanism, for surviving the app being
/// backgrounded or OS-killed for an extended period). That's real,
/// separate, higher-risk platform-plugin work, deliberately left for
/// its own pass rather than folded in here. The triggers below already
/// satisfy Phase 0's own exit criterion (create offline -> kill ->
/// restart -> reconnect), since a fresh launch's own connectivity check
/// covers exactly that scenario without needing OS-level background
/// scheduling.
class SyncTriggers with WidgetsBindingObserver {
  SyncTriggers({required SyncEngine syncEngine, Connectivity? connectivity})
      : _syncEngine = syncEngine,
        _connectivity = connectivity ?? Connectivity();

  final SyncEngine _syncEngine;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Starts listening. Called once from bootstrap.dart — Section 8:
  /// "a single, always-available background service... never
  /// re-instantiated per screen."
  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);

    // connectivity_plus has a known real gap: onConnectivityChanged
    // doesn't reliably emit an initial event on every platform/starting
    // state (most notably when the starting state is genuinely `none`).
    // Checking explicitly here, rather than trusting the stream's first
    // emission, covers the case this checkpoint's own exit criterion
    // describes: the app launches already back online with items
    // queued from a previous offline session.
    await _runIfOnline();

    _subscription = _connectivity.onConnectivityChanged.listen((_) {
      unawaited(_runIfOnline());
    });
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
  }

  /// Section 8's app-foreground trigger — a necessary backup to the
  /// connectivity stream specifically because Android stops delivering
  /// connectivity-change events to backgrounded apps starting with
  /// Android 8 (Oreo) — confirmed directly in connectivity_plus's own
  /// documentation, not assumed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfOnline());
    }
  }

  /// Section 8's manual "Sync Now" (Volume 11) — bypasses the
  /// attempts-based backoff gate entirely (SyncEngine's `manual: true`),
  /// unlike every other trigger here.
  Future<void> syncNow() => _syncEngine.runOnce(manual: true);

  /// Section 8's fourth trigger ("new item enqueued while already
  /// online") — exposed for SyncQueue.setOnEnqueued, kept out of
  /// SyncQueue itself so that class stays free of any
  /// connectivity/Flutter dependency (see sync_queue.dart's own
  /// comment on why that wiring happens via a setter, after
  /// construction, rather than a constructor parameter).
  Future<void> notifyEnqueued() => _runIfOnline();

  Future<void> _runIfOnline() async {
    // connectivity_plus 6.0.4 is a post-6.0 breaking-change release:
    // both checkConnectivity() and onConnectivityChanged return/emit
    // List<ConnectivityResult> now, not a single ConnectivityResult —
    // confirmed directly against connectivity_plus's own current
    // documentation and changelog rather than assumed from older
    // examples (most existing tutorials still show the pre-6.0,
    // single-result API).
    final results = await _connectivity.checkConnectivity();
    if (_hasConnectivity(results)) {
      unawaited(_syncEngine.runOnce());
    }
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
