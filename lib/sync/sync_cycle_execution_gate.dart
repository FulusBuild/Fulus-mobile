import 'dart:async';

/// Serializes synchronization cycles within one runtime and coalesces mutations
/// committed while a cycle is in flight into one follow-up attempt.
///
/// Cross-runtime exclusion remains the responsibility of SyncExecutionLease.
/// This primitive only owns same-runtime cycle/follow-up coordination.
class SyncCycleExecutionGate {
  SyncCycleExecutionGate({
    required Future<bool> Function({bool manual}) runCycle,
    required Future<bool> Function() runFollowUp,
    required bool Function() isActive,
    required void Function(Object error, StackTrace stackTrace) onFollowUpError,
  })  : _runCycle = runCycle,
        _runFollowUp = runFollowUp,
        _isActive = isActive,
        _onFollowUpError = onFollowUpError;

  final Future<bool> Function({bool manual}) _runCycle;
  final Future<bool> Function() _runFollowUp;
  final bool Function() _isActive;
  final void Function(Object error, StackTrace stackTrace) _onFollowUpError;

  Future<bool>? _activeCycle;
  Future<void>? _followUp;
  bool _followUpRequested = false;

  bool get isRunning => _activeCycle != null;
  Future<void>? get followUp => _followUp;

  Future<bool> run({bool manual = false}) async {
    final active = _activeCycle;
    if (active != null) return active;

    late Future<bool> run;
    run = _runCycle(manual: manual);
    _activeCycle = run;
    try {
      return await run;
    } finally {
      final requested = _followUpRequested;
      _followUpRequested = false;
      if (identical(_activeCycle, run)) {
        _activeCycle = null;
      }
      if (requested && _isActive()) {
        _scheduleFollowUp();
      }
    }
  }

  void requestAfterCurrentCycle() {
    if (_activeCycle == null) return;
    _followUpRequested = true;
  }

  Future<void> waitForIdle() async {
    while (true) {
      final cycle = _activeCycle;
      if (cycle != null) {
        await cycle;
        continue;
      }
      final followUp = _followUp;
      if (followUp != null) {
        await followUp;
        continue;
      }
      return;
    }
  }

  void _scheduleFollowUp() {
    final completer = Completer<void>();
    _followUp = completer.future;
    Timer.run(() async {
      try {
        await _runFollowUp();
      } catch (error, stackTrace) {
        _onFollowUpError(error, stackTrace);
      } finally {
        if (identical(_followUp, completer.future)) {
          _followUp = null;
        }
        if (!completer.isCompleted) completer.complete();
      }
    });
  }

  void dispose() {
    _followUpRequested = false;
  }
}
