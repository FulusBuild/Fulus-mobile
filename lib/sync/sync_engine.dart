import 'dart:async';

import 'package:drift/drift.dart';

import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';
import '../core/errors/failure.dart';
import '../data/local/database/database.dart';
import 'conflict_resolver.dart';
import 'retry_policy.dart';
import 'sync_handler.dart';

/// Queue-draining engine. A failed item remains durable in the queue, while
/// independent items are still given a chance to sync in the same run.
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required Map<String, SyncHandler> handlersByEntityType,
    this.maxAttemptsBeforeAttentionNeeded = 5,
    RetryPolicy retryPolicy = const RetryPolicy(),
    ConflictResolver conflictResolver = const ConflictResolver(),
    DiagnosticLogger? diagnosticLogger,
    Future<bool> Function()? canSync,
  })  : _db = db,
        _handlersByEntityType = handlersByEntityType,
        _retryPolicy = retryPolicy,
        _conflictResolver = conflictResolver,
        _diagnosticLogger = diagnosticLogger,
        _canSync = canSync;

  final AppDatabase _db;
  final Map<String, SyncHandler> _handlersByEntityType;
  final RetryPolicy _retryPolicy;
  final ConflictResolver _conflictResolver;
  final DiagnosticLogger? _diagnosticLogger;
  final Future<bool> Function()? _canSync;
  final int maxAttemptsBeforeAttentionNeeded;

  Future<void>? _activeRun;
  bool _isRunning = false;

  Future<void> runOnce({bool manual = false}) {
    final active = _activeRun;
    if (active != null) return active;
    final run = _runOnce(manual: manual);
    late Future<void> tracked;
    tracked = run.whenComplete(() {
      if (identical(_activeRun, tracked)) _activeRun = null;
    });
    _activeRun = tracked;
    return tracked;
  }

  Future<void> _runOnce({required bool manual}) async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      await _drainQueue(manual: manual);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _drainQueue({required bool manual}) async {
    final canSync = _canSync;
    if (canSync != null && !await canSync()) return;

    final query = _db.select(_db.syncQueueItems)
      ..orderBy([
        (q) => OrderingTerm.asc(q.priority),
        (q) => OrderingTerm.asc(q.enqueuedAt),
      ]);

    if (!manual) {
      query.where((q) => q.syncAttempts.isSmallerThanValue(
            maxAttemptsBeforeAttentionNeeded,
          ));
    }

    final items = await query.get();
    final now = DateTime.now();

    for (final item in items) {
      final wouldCrossThreshold =
          item.syncAttempts + 1 >= maxAttemptsBeforeAttentionNeeded;
      if (!manual &&
          !wouldCrossThreshold &&
          !_retryPolicy.isEligibleForRetry(
            syncAttempts: item.syncAttempts,
            lastAttemptedAt: item.lastAttemptedAt,
            now: now,
          )) {
        continue;
      }

      final handler = _handlersByEntityType[item.entityType];
      if (handler == null) {
        final message =
            'No sync handler registered for entityType "${item.entityType}".';
        await _markAttentionNeeded(item.id, error: message);
        unawaited(_captureSyncFailure(
          item: item,
          error: StateError(message),
          stackTrace: StackTrace.current,
        ));
        continue;
      }

      try {
        await handler.sync(item);
        await _removeFromQueue(item.id);
      } on BusinessRuleFailure catch (e, st) {
        final message = _conflictResolver.looksLikeConflict(e.message)
            ? _conflictResolver.annotate(e.message)
            : e.message;
        await _markAttentionNeeded(item.id, error: message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
      } on ValidationFailure catch (e, st) {
        await _markAttentionNeeded(item.id, error: e.message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
      } on AuthFailure catch (e, st) {
        await _markAttentionNeeded(item.id, error: e.message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
      } catch (e, st) {
        final attempts = item.syncAttempts + 1;
        if (attempts >= maxAttemptsBeforeAttentionNeeded) {
          await _markAttentionNeeded(item.id, error: e.toString());
          unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
        } else {
          await _recordAttempt(item.id, attempts: attempts, error: e.toString());
        }
        // One failed queue item must not prevent independent items from
        // syncing. This matters especially during migration from the old
        // API layer: a stale/unsupported item should not starve newer Fulus
        // cloud operations behind it.
        continue;
      }
    }
  }

  Future<void> _captureSyncFailure({
    required dynamic item,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    final logger = _diagnosticLogger;
    if (logger == null) return;
    await logger.captureError(
      error: error,
      stackTrace: stackTrace,
      severity: DiagnosticSeverity.warning,
      category: DiagnosticCategory.synchronization,
      component: 'SyncEngine',
      operation: 'runOnce',
      context: {
        'Entity type': '${item.entityType}',
        'Sync attempts': '${item.syncAttempts}',
        'syncOutcome': 'attentionNeeded',
      },
    );
  }

  Future<void> _removeFromQueue(String id) async {
    await (_db.delete(_db.syncQueueItems)..where((q) => q.id.equals(id))).go();
  }

  Future<void> _recordAttempt(
    String id, {
    required int attempts,
    required String error,
  }) async {
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        syncAttempts: Value(attempts),
        lastError: Value(error),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _markAttentionNeeded(
    String id, {
    required String error,
  }) async {
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        syncAttempts: Value(maxAttemptsBeforeAttentionNeeded),
        lastError: Value(error),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }
}
