import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_status_notifier.dart';

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
///
/// **Stage 16 (Sync Layer Repositioning):** every method below now
/// checks [SyncConfig.isEnabled] before doing anything that touches
/// connectivity or the network — this is deliberately where that
/// enforcement lives (rather than only at the bootstrap.dart call site
/// that constructs this class) specifically so the invariant holds even
/// if a future caller reaches one of these methods some other way (a
/// Settings "Sync Now" button, SyncQueue's enqueued-callback) without
/// separately checking the flag itself first. See SyncConfig's own doc
/// comment for why the toggle defaults to disabled.
class SyncTriggers with WidgetsBindingObserver {
  SyncTriggers({
    required SyncEngine syncEngine,
    required SyncConfig syncConfig,
    required SyncStatusNotifier syncStatusNotifier,
    Connectivity? connectivity,
  })  : _syncEngine = syncEngine,
        _syncConfig = syncConfig,
        _syncStatusNotifier = syncStatusNotifier,
        _connectivity = connectivity ?? Connectivity();

  final SyncEngine _syncEngine;
  final SyncConfig _syncConfig;
  final SyncStatusNotifier _syncStatusNotifier;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;

  /// Starts listening. Called once from bootstrap.dart — Section 8:
  /// "a single, always-available background service... never
  /// re-instantiated per screen."
  ///
  /// When sync is disabled (the default — SyncConfig.isEnabled ==
  /// false), this returns immediately without registering the
  /// WidgetsBindingObserver or subscribing to connectivity changes at
  /// all — not merely skipping what they'd trigger. That's a deliberate
  /// choice over registering-but-gating-the-callback: it means a
  /// disabled sync layer has genuinely nothing listening, not
  /// listeners that are attached but always no-op, which is the more
  /// literal reading of "the application must function 100% without
  /// synchronization" (this stage's own rule) — nothing related to sync
  /// is running at all, not just "running harmlessly."
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

  /// Section 8's app-foreground trigger — a necessary backup to the
  /// connectivity stream specifically because Android stops delivering
  /// connectivity-change events to backgrounded apps starting with
  /// Android 8 (Oreo) — confirmed directly in connectivity_plus's own
  /// documentation, not assumed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_syncConfig.isEnabled) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfOnline());
    }
  }

  /// Section 8's manual "Sync Now" (Volume 11) — bypasses the
  /// attempts-based backoff gate entirely (SyncEngine's `manual: true`),
  /// unlike every other trigger here.
  ///
  /// Throws (rather than silently no-op-ing, unlike the
  /// framework-triggered methods below) when sync is disabled — every
  /// OTHER method here can legitimately fire on its own from the OS or
  /// Flutter itself with no user in the loop to tell, so silence is
  /// correct for those; a "Sync Now" button, by contrast, should only
  /// ever be reachable from UI that already checked
  /// SyncStatusNotifier and wouldn't show the button at all while
  /// disabled (Volume 11's own framing) — reaching this method while
  /// disabled anyway means that UI-side check was skipped, which is a
  /// real bug worth surfacing loudly during development rather than
  /// swallowing.
  Future<void> syncNow() async {
    if (!_syncConfig.isEnabled) {
      throw StateError(
        'SyncTriggers.syncNow() was called while sync is disabled. '
        'Callers should only expose a "Sync Now" action when '
        'SyncStatusNotifier reports sync as enabled.',
      );
    }
    await _syncEngine.runOnce(manual: true);
    await _syncStatusNotifier.checkForStuckSyncAndNotify();
  }

  /// Section 8's fourth trigger ("new item enqueued while already
  /// online") — exposed for SyncQueue.setOnEnqueued, kept out of
  /// SyncQueue itself so that class stays free of any
  /// connectivity/Flutter dependency (see sync_queue.dart's own
  /// comment on why that wiring happens via a setter, after
  /// construction, rather than a constructor parameter).
  Future<void> notifyEnqueued() async {
    if (!_syncConfig.isEnabled) return;
    await _runIfOnline();
  }

  Future<void> _runIfOnline() async {
    if (!_syncConfig.isEnabled) return;

    // connectivity_plus 6.0.4 is a post-6.0 breaking-change release:
    // both checkConnectivity() and onConnectivityChanged return/emit
    // List<ConnectivityResult> now, not a single ConnectivityResult —
    // confirmed directly against connectivity_plus's own current
    // documentation and changelog rather than assumed from older
    // examples (most existing tutorials still show the pre-6.0,
    // single-result API).
    final results = await _connectivity.checkConnectivity();
    if (_hasConnectivity(results)) {
      unawaited(_runAndCheckStuck());
    }
  }

  Future<void> _runAndCheckStuck() async {
    await _syncEngine.runOnce();
    // Volume 12 Decision 43's second notification trigger — checked
    // after every automatic drain attempt, not just after manual Sync
    // Now, since "pending data that's stayed unsynced for an unusually
    // long time despite the device showing as online" is just as true
    // (arguably more likely to first be noticed) via the automatic path.
    await _syncStatusNotifier.checkForStuckSyncAndNotify();
  }

  bool _hasConnectivity(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
