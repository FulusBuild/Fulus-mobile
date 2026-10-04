import 'dart:async';

import '../core/errors/failure.dart';
import 'sync_engine.dart';
import 'sync_execution_lease.dart';

/// Internal semantic operation for executing one complete synchronization
/// cycle.
///
/// SyncTriggers is deliberately only the event adapter. This runner owns the
/// push/pull sequencing and the recovery policy that belongs to a sync cycle,
/// while SyncEngine remains responsible for durable outbound queue draining
/// and SyncExecutionLease remains responsible for cross-runtime exclusion.
class SyncCycleRunner {
  SyncCycleRunner({
    required SyncEngine syncEngine,
    required SyncExecutionLease executionLease,
    Future<bool> Function()? hasOutboundWork,
    Future<void> Function()? onPushSuccess,
    Future<void> Function()? pullFromServer,
    Future<void> Function()? onCursorTooOldRecovery,
    Future<void> Function()? onRecoveryReconciled,
    Future<void> Function(Object error)? onRecoveryFailed,
    Future<void> Function()? onBeforeSyncCycle,
  })  : _syncEngine = syncEngine,
        _executionLease = executionLease,
        _hasOutboundWork = hasOutboundWork,
        _onPushSuccess = onPushSuccess,
        _pullFromServer = pullFromServer,
        _onCursorTooOldRecovery = onCursorTooOldRecovery,
        _onRecoveryReconciled = onRecoveryReconciled,
        _onRecoveryFailed = onRecoveryFailed,
        _onBeforeSyncCycle = onBeforeSyncCycle;

  final SyncEngine _syncEngine;
  final SyncExecutionLease _executionLease;
  final Future<bool> Function()? _hasOutboundWork;
  final Future<void> Function()? _onPushSuccess;
  final Future<void> Function()? _pullFromServer;
  final Future<void> Function()? _onCursorTooOldRecovery;
  final Future<void> Function()? _onRecoveryReconciled;
  final Future<void> Function(Object error)? _onRecoveryFailed;
  final Future<void> Function()? _onBeforeSyncCycle;
  bool _beforeSyncCycleCompleted = false;

  Future<void> run({bool manual = false}) async {
    final lease = _executionLease;
    if (!await lease.acquire()) return;

    try {
      try {
        if (!_beforeSyncCycleCompleted) {
          await _onBeforeSyncCycle?.call();
          _beforeSyncCycleCompleted = true;
        }
        await _perform(manual: manual, lease: lease);
      } on SyncExecutionLeaseLost {
        // Another runtime took ownership after this runtime was suspended.
        // The current cycle must stop without starting a later recovery phase.
      }
    } finally {
      await lease.release();
    }
  }

  Future<void> _perform({
    required bool manual,
    required SyncExecutionLease lease,
  }) async {
    final hadOutboundWork = await _hasOutboundWork?.call() ?? false;
    await _syncEngine.runOnce(manual: manual);
    await lease.ensureHeld();
    await _onPushSuccess?.call(hadOutboundWork);
    await lease.ensureHeld();

    final pull = _pullFromServer;
    if (pull == null) return;

    var recoveredFromStaleCursor = false;
    try {
      await pull();
      await lease.ensureHeld();
    } on BusinessRuleFailure catch (error) {
      if (error.code != 'SYNC_CURSOR_TOO_OLD') rethrow;

      final recover = _onCursorTooOldRecovery;
      if (recover == null) rethrow;

      await lease.ensureHeld();
      await recover();
      await lease.ensureHeld();
      recoveredFromStaleCursor = true;

      try {
        await pull();
        await lease.ensureHeld();
      } catch (error) {
        await _onRecoveryFailed?.call(error);
        rethrow;
      }
    }

    if (!recoveredFromStaleCursor) return;

    try {
      await _onRecoveryReconciled?.call();
    } catch (error) {
      await _onRecoveryFailed?.call(error);
      rethrow;
    }
  }
}
