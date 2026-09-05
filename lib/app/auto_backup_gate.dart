import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Activity-triggered backup — the "like WhatsApp" half of Backup &
/// Restore. [dataRefreshSignalProvider] already fires after every
/// data-changing action anywhere in the app (a sale, a stock movement,
/// an expense, a repayment, a daily close — see that provider's own
/// doc comment in providers.dart for the full list), so this widget is
/// the one place that turns "something happened" into "keep the
/// automatic backup current," without any of those call sites needing
/// to know backups exist at all.
///
/// Debounced rather than run on every single signal: a busy till can
/// bump the signal several times a minute, and each run is a real
/// VACUUM INTO over the live database (see BackupRepositoryImpl's own
/// doc comment) — worth doing once activity settles, not once per tap.
/// [_scheduleBackup] restarts [_debounceDuration] on every new signal;
/// [_running] is a simple non-overlap guard, not a queue — if activity
/// keeps arriving while a backup is already mid-flight, that's fine,
/// the timer it restarted fires again once things settle, same as any
/// other burst.
///
/// Wrapped around the whole app in app.dart, alongside AppLockGate, so
/// it's alive for as long as the app is, regardless of which screen or
/// tab is on top — same reasoning that widget's own doc comment gives
/// for using MaterialApp.router's builder hook rather than a route of
/// its own. Purely a logic wrapper: [build] never changes what's on
/// screen, so where it sits relative to AppLockGate doesn't matter.
class AutoBackupGate extends ConsumerStatefulWidget {
  const AutoBackupGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AutoBackupGate> createState() => _AutoBackupGateState();
}

class _AutoBackupGateState extends ConsumerState<AutoBackupGate> {
  static const _debounceDuration = Duration(seconds: 10);

  Timer? _debounce;
  bool _running = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleBackup() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _runBackup);
  }

  Future<void> _runBackup() async {
    if (_running) return;
    _running = true;
    try {
      await ref.read(backupRepositoryProvider).runAutoBackup();
    } catch (_) {
      // Best-effort and silent, deliberately — this is a background
      // convenience running after ordinary app use, not an action the
      // person took. A snackbar for a failed backup nobody asked for
      // right now would be noise; the in-app backups list (More ->
      // Settings -> Backup & Restore) is what tells the honest story
      // of whether auto-backup is keeping up, not an interruption in
      // the moment it fails.
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(dataRefreshSignalProvider, (previous, next) {
      if (previous != null && previous != next) _scheduleBackup();
    });
    return widget.child;
  }
}
