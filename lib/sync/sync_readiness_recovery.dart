import 'dart:async';

/// Internal scheduler for readiness recovery after device/session authority
/// is lost during an active sync cycle.
///
/// It owns only deferred timing. It deliberately knows nothing about sync
/// engines, leases, connectivity, or readiness semantics.
class SyncReadinessRecovery {
  SyncReadinessRecovery({
    required bool Function() isActive,
    required bool Function() canRun,
    required Future<bool> Function() recover,
    required void Function(Object error, StackTrace stackTrace) onFailure,
    Duration interval = const Duration(milliseconds: 250),
  })  : _isActive = isActive,
        _canRun = canRun,
        _recover = recover,
        _onFailure = onFailure,
        _interval = interval;

  final bool Function() _isActive;
  final bool Function() _canRun;
  final Future<bool> Function() _recover;
  final void Function(Object error, StackTrace stackTrace) _onFailure;
  final Duration _interval;
  Timer? _timer;

  void schedule() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  void _poll() {
    if (!_isActive()) {
      dispose();
      return;
    }
    if (!_canRun()) return;

    dispose();
    unawaited(_recover().catchError((Object error, StackTrace stackTrace) {
      _onFailure(error, stackTrace);
      return false;
    }));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
