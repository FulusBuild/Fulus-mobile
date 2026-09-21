import 'dart:async';

import 'package:drift/drift.dart';

import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';
import '../core/errors/failure.dart';
import '../data/local/database/database.dart';
import 'conflict_resolver.dart';
import 'retry_policy.dart';
import 'sync_error.dart';
import 'sync_handler.dart';

/// Durable queue-draining engine. A failed item remains in the queue, while
/// independent items still get a chance to sync in the same cycle.
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
  bool _rerunRequested = false;

  Future<void> runOnce({bool manual = false}) {
    final active = _activeRun;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    final run = _runOnce(manual: manual);
    late Future<void> tracked;
    tracked = run.whenComplete(() {
      if (!identical(_activeRun, tracked)) return;
      _activeRun = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        // Work may have been enqueued after this drain captured its queue
        // snapshot. Start one follow-up drain after the current future has
        // settled so the newly-enqueued item cannot be stranded behind an
        // already-running cycle.
        unawaited(runOnce());
      }
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
      } on SyncFailure catch (e, st) {
        await _handleClassifiedFailure(item, e, st);
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
        // Authentication is a session-level condition, not a permanent
        // queue-item failure. Keep the item retryable and stop this drain
        // cycle until the session is restored; otherwise one expired session
        // would permanently park every queued write as attention-needed.
        await _resetAfterAuthenticationFailure(item.id, error: e.message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
        return;
      } catch (e, st) {
        final classified = SyncFailure.classify(e);
        await _handleClassifiedFailure(item, classified, st);
      }
    }
  }

  Future<void> _handleClassifiedFailure(
    SyncQueueItem item,
    SyncFailure failure,
    StackTrace stackTrace,
  ) async {
    final attempts = item.syncAttempts + 1;
    if (!failure.shouldRetry || attempts >= maxAttemptsBeforeAttentionNeeded) {
      await _markAttentionNeeded(item.id, error: failure.message);
    } else {
      await _recordAttempt(
        item.id,
        attempts: attempts,
        error: failure.message,
      );
    }
    unawaited(_captureSyncFailure(
      item: item,
      error: failure,
      stackTrace: stackTrace,
    ));
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
        'syncOutcome': error is SyncFailure && error.shouldRetry
            ? 'retry'
            : 'attentionNeeded',
      },
    );
  }

  Future<void> _removeFromQueue(String id) async {
    await (_db.delete(_db.syncQueueItems)..where((q) => q.id.equals(id))).go();
  }

  Future<void> _resetAfterAuthenticationFailure(
    String id, {
    required String error,
  }) async {
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        syncAttempts: const Value(0),
        lastError: Value(error),
        lastAttemptedAt: const Value(null),
      ),
    );
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
