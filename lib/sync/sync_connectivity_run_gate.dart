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

  Future<bool> run() {
    final active = _active;
    if (active != null) return active;

    // Publish the in-flight future before invoking the callback. The callback
    // may synchronously re-enter this gate before its first await; publishing
    // first keeps that re-entry coalesced rather than creating a second run.
    final completer = Completer<bool>();
    final future = completer.future;
    _active = future;
    // Start the callback in a microtask so the published future is visible
    // before user code can re-enter the gate.
    unawaited(Future.microtask(() => _execute(future, completer)));
    return future;
  }

  Future<void> _execute(
    Future<bool> future,
    Completer<bool> completer,
  ) async {
    try {
      completer.complete(await _run());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
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
