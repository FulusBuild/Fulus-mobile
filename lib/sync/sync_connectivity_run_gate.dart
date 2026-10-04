import 'dart:async';

/// Serializes connectivity-gated synchronization attempts within one runtime.
///
/// Multiple lifecycle, connectivity, and recovery signals may arrive together.
/// They share one in-flight attempt instead of starting duplicate readiness or
/// sync work. The actual readiness and sync operations remain outside this
/// primitive.
class SyncConnectivityRunGate {
  SyncConnectivityRunGate({
    required Future<bool> Function() run,
  }) : _run = run;

  final Future<bool> Function() _run;
  Future<bool>? _active;

  bool get isRunning => _active != null;

  Future<bool> run() async {
    final active = _active;
    if (active != null) return active;

    final future = _run();
    _active = future;
    try {
      return await future;
    } finally {
      if (identical(_active, future)) {
        _active = null;
      }
    }
  }

  Future<void> waitForIdle() async {
    final active = _active;
    if (active != null) await active;
  }
}
