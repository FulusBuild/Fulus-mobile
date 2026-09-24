import 'dart:async';

import 'package:drift/drift.dart';

import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';
import '../core/errors/failure.dart';
import '../data/local/database/database.dart';
import 'conflict_resolver.dart';
import 'retry_policy.dart';
import 'sync_error.dart';
import 'sync_execution_lease.dart';
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
    Future<void> Function()? onDeviceAuthorizationLost,
    SyncExecutionLease? executionLease,
  })  : _db = db,
        _handlersByEntityType = handlersByEntityType,
        _retryPolicy = retryPolicy,
        _conflictResolver = conflictResolver,
        _diagnosticLogger = diagnosticLogger,
        _canSync = canSync,
        _onDeviceAuthorizationLost = onDeviceAuthorizationLost,
        _executionLease = executionLease;

  final AppDatabase _db;
  final Map<String, SyncHandler> _handlersByEntityType;
  final RetryPolicy _retryPolicy;
  final ConflictResolver _conflictResolver;
  final DiagnosticLogger? _diagnosticLogger;
  final Future<bool> Function()? _canSync;
  final Future<void> Function()? _onDeviceAuthorizationLost;
  final SyncExecutionLease? _executionLease;
  final int maxAttemptsBeforeAttentionNeeded;

  Future<void>? _activeRun;
  bool _isRunning = false;

  Future<void> runOnce({bool manual = false}) {
    final active = _activeRun;
    if (active != null) return active;

    late Future<void> tracked;
    tracked = _runOnce(manual: manual).whenComplete(() {
      if (identical(_activeRun, tracked)) {
        _activeRun = null;
      }
    });
    _activeRun = tracked;
    return tracked;
  }

  Future<void> _runOnce({required bool manual}) async {
    if (_isRunning) return;

    final lease = _executionLease;
    if (lease != null && !await lease.acquire()) {
      // Another Fulus runtime is already synchronizing. A later foreground
      // trigger or WorkManager invocation will retry after that runtime
      // releases the SQLite lease. Most importantly, never let two runtimes
      // mutate the same outbox/cursor concurrently.
      return;
    }

    _isRunning = true;
    try {
      await _drainQueue(manual: manual);
    } finally {
      _isRunning = false;
      await lease?.release();
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

    final items = await query.get();
    final now = DateTime.now();

    // Dependency failures are deferred so a prerequisite later in the same
    // queue snapshot can settle during this drain. This avoids leaving a
    // dependent item waiting for an unrelated future trigger.
    var pending = items;
    while (pending.isNotEmpty) {
      final deferred = <SyncQueueItem>[];
      var progress = false;

      for (final item in pending) {
      // Retryable work keeps retrying after the attention threshold, using
      // the capped backoff. Permanent failures are explicitly parked with a
      // [BLOCKED] marker and remain out of automatic retries until a user or
      // a newer local mutation resolves them.
      if (!manual && _isBlocked(item)) continue;
      if (!manual &&
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
        progress = true;
      } on SyncFailure catch (e, st) {
        if (e.kind == SyncErrorKind.dependencyNotReady) {
          deferred.add(item);
          continue;
        }
        await _handleClassifiedFailure(item, e, st);
      } on BusinessRuleFailure catch (e, st) {
        final isConflict = e.code == 'IDEMPOTENCY_CONFLICT' ||
            e.code == 'SYNC_CONFLICT' ||
            _conflictResolver.looksLikeConflict(e.message);
        final message = isConflict
            ? _conflictResolver.annotate(e.message)
            : e.message;
        if (isConflict) {
          await _recordConflict(item, e, message);
        }
        await _markAttentionNeeded(item.id, error: message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
      } on ValidationFailure catch (e, st) {
        await _markAttentionNeeded(item.id, error: e.message);
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
      } on AuthFailure catch (e, st) {
        // Authentication is a session-level condition, not a permanent
        // queue-item failure. Likewise, a server-revoked installation is a
        // device-registration condition: clear the cached registration and
        // let the normal readiness path silently re-register this same
        // device. Neither condition should permanently park queued writes.
        await _resetAfterAuthenticationFailure(item.id, error: e.message);
        if (e.requiresDeviceRegistration) {
          await _onDeviceAuthorizationLost?.call();
        }
        unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
        return;
      } catch (e, st) {
        final classified = SyncFailure.classify(e);
        if (classified.kind == SyncErrorKind.dependencyNotReady) {
          deferred.add(item);
          continue;
        }
        await _handleClassifiedFailure(item, classified, st);
      }
      }

      if (!progress || deferred.isEmpty) break;
      pending = deferred;
    }
  }

  Future<void> _handleClassifiedFailure(
    SyncQueueItem item,
    SyncFailure failure,
    StackTrace stackTrace,
  ) async {
    final attempts = item.syncAttempts + 1;
    if (!failure.shouldRetry) {
      await _markAttentionNeeded(item.id, error: failure.message);
    } else {
      await _recordAttempt(
        item.id,
        attempts: attempts > maxAttemptsBeforeAttentionNeeded
            ? maxAttemptsBeforeAttentionNeeded
            : attempts,
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

  Future<void> _recordConflict(
    SyncQueueItem item,
    BusinessRuleFailure failure,
    String message,
  ) async {
    // The operation id is the durable identity of this parked conflict.
    // Upsert makes repeated delivery idempotent while ensuring a machine-
    // readable conflict can never be lost because a stale duplicate row was
    // observed during a concurrent drain.
    await _db.into(_db.syncConflictRecords).insertOnConflictUpdate(
      SyncConflictRecordsCompanion.insert(
        id: item.id + ':conflict',
        operationId: item.id,
        entityType: item.entityType,
        entityLocalId: item.entityLocalId,
        code: Value(failure.code),
        message: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _removeFromQueue(String id) async {
    await _db.transaction(() async {
      final queueRow = await (_db.select(_db.syncQueueItems)
            ..where((q) => q.id.equals(id)))
          .getSingleOrNull();
      await (_db.delete(_db.syncQueueItems)..where((q) => q.id.equals(id))).go();
      if (queueRow != null) {
        final conflicts = await (_db.select(_db.syncConflictRecords)
              ..where((c) => c.entityType.equals(queueRow.entityType))
              ..where((c) => c.entityLocalId.equals(queueRow.entityLocalId))
              ..where((c) => c.resolvedAt.isNull()))
            .get();

        // A newer successful mutation supersedes older parked mutations for
        // the same local entity. Resolve the conflict record and remove its
        // stale outbox row together, otherwise a manual retry could later
        // replay an obsolete mutation over the already-accepted state.
        for (final conflict in conflicts) {
          final conflictedQueue = await (_db.select(_db.syncQueueItems)
                ..where((q) => q.id.equals(conflict.operationId)))
              .getSingleOrNull();
          if (conflictedQueue != null &&
              conflictedQueue.enqueuedAt.isAfter(queueRow.enqueuedAt)) {
            continue;
          }
          if (conflictedQueue != null && conflictedQueue.id != queueRow.id) {
            await (_db.delete(_db.syncQueueItems)
                  ..where((q) => q.id.equals(conflictedQueue.id)))
                .go();
          }
          await (_db.update(_db.syncConflictRecords)
                ..where((c) => c.id.equals(conflict.id)))
              .write(
            SyncConflictRecordsCompanion(
              resolvedAt: Value(DateTime.now()),
              resolution: const Value('superseded_by_successful_entity_update'),
            ),
          );
        }
      }
    });
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

  bool _isBlocked(SyncQueueItem item) {
    final error = item.lastError ?? '';
    return error.startsWith('[BLOCKED]') || error.startsWith('[CONFLICT]');
  }

  Future<void> _markAttentionNeeded(
    String id, {
    required String error,
  }) async {
    final storedError = error.startsWith('[BLOCKED]') || error.startsWith('[CONFLICT]')
        ? error
        : '[BLOCKED] $error';
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        syncAttempts: Value(maxAttemptsBeforeAttentionNeeded),
        lastError: Value(storedError),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }
}
