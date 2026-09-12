import 'dart:async';

import 'package:drift/drift.dart';

import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';
import '../core/errors/failure.dart';
import '../data/local/database/database.dart';
import 'conflict_resolver.dart';
import 'retry_policy.dart';
import 'sync_handler.dart';

/// Architecture Section 8's queue-draining engine. Deliberately pure
/// Dart — Drift and this codebase's own Failure hierarchy are its only
/// real dependencies, no Flutter/connectivity_plus/workmanager imports
/// at all. The platform-specific triggers that decide WHEN to call
/// [runOnce] (connectivity changes, app-foreground, WorkManager) live in
/// sync_triggers.dart instead — the same layering split this codebase
/// already applies elsewhere (domain has zero Flutter/Drift imports;
/// here, the queue-draining ALGORITHM stays just as testable, with only
/// the trigger wiring depending on Flutter/platform plugins).
///
/// A single instance is constructed once in bootstrap.dart and never
/// re-instantiated per screen, per Section 8's explicit statement.
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

  /// Optional, and deliberately so — everything else this class depends
  /// on is plain Dart (see this class's own header comment on staying
  /// Flutter-free and independently testable). DiagnosticLogger itself
  /// has no Flutter *UI* dependency either, but its DeviceContextProvider
  /// does reach device_info_plus/package_info_plus (real platform-channel
  /// plugins) several layers down — nullable-with-a-safe-no-op default
  /// keeps every existing call site and test that constructs a
  /// SyncEngine without this parameter completely unaffected, and keeps
  /// this class constructible in a plain `dart test` context that never
  /// touches a platform channel, exactly as before.
  final DiagnosticLogger? _diagnosticLogger;

  /// Optional cloud authorization gate. A null gate preserves the existing
  /// local-only/test behavior; when supplied, a false result leaves the
  /// durable queue untouched and simply skips this run.
  final Future<bool> Function()? _canSync;

  /// Architecture Section 8 names this as "a bounded number" without
  /// specifying the exact count — 5 chosen here as a reasonable default
  /// for a foundation phase; Section 8 doesn't require a specific value,
  /// so this is my own choice, not a figure verified against the brief.
  final int maxAttemptsBeforeAttentionNeeded;

  bool _isRunning = false;
  Future<void>? _activeRun;

  /// Drains the queue once. Safe to call from multiple trigger sources
  /// close together (connectivity-regained and app-foregrounded firing
  /// within the same second, say) — a run already in progress makes a
  /// concurrent call a no-op rather than two runs racing over the same
  /// queue rows.
  ///
  /// [manual] corresponds to Volume 11's "Sync Now" (Architecture
  /// Section 8's third trigger) — "bypassing any backoff state
  /// currently in effect." When false (every automatic trigger), items
  /// that have already crossed [maxAttemptsBeforeAttentionNeeded] are
  /// excluded from this run; when true, every pending item is eligible
  /// again, on the chance whatever made it fail has since changed.
  Future<void> runOnce({bool manual = false}) {
    final active = _activeRun;
    if (active != null) return active;

    final run = _runOnce(manual: manual);
    _activeRun = run;
    return run.whenComplete(() {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    });
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
    // Priority lanes first, oldest-first within each lane — Section 8
    // states both rules ("oldest-first ordering by default" and three
    // priority lanes) without saying explicitly which wins; ordering by
    // (priority, enqueuedAt) together is the one reading that honors
    // both simultaneously rather than picking one over the other.
    final query = _db.select(_db.syncQueueItems)
      ..orderBy([
        (q) => OrderingTerm.asc(q.priority),
        (q) => OrderingTerm.asc(q.enqueuedAt),
      ]);

    if (!manual) {
      query.where(
        (q) => q.syncAttempts.isSmallerThanValue(
          maxAttemptsBeforeAttentionNeeded,
        ),
      );
    }

    final items = await query.get();
    final now = DateTime.now();

    for (final item in items) {
      // RetryPolicy's own eligibility check, not the SQL query above —
      // "has this item failed recently enough that it's not worth
      // trying again yet" depends on syncAttempts AND lastAttemptedAt
      // together (an exponential function of the first, applied to the
      // second), which isn't expressible as a static column comparison
      // the way the syncAttempts-below-threshold filter above is.
      // [manual] bypasses this entirely — same "Sync Now" contract this
      // method's own doc comment already states for the threshold
      // filter above, extended to backoff for the same reason.
      // Whether the attempt about to be made would itself cross
      // maxAttemptsBeforeAttentionNeeded — this item's last real
      // chance before it's flagged and stops being retried
      // automatically at all. Backoff is skipped for that one attempt:
      // otherwise an item could sit fully backed off (up to
      // [RetryPolicy.maxDelay]) without ever reaching the threshold,
      // silently retried forever instead of promptly surfacing as
      // attentionNeeded with a current error. Below the threshold,
      // normal backoff still applies exactly as before.
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
        // No handler registered for this entityType — a real
        // programming error (something enqueued a task this engine was
        // never told how to process), not a transient failure. Flagged
        // immediately rather than retried, since retrying can never fix
        // a missing handler, and the run continues — this says nothing
        // about whether the server itself is reachable.
        final message = 'No sync handler registered for entityType '
            '"${item.entityType}".';
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
        // A 409 that reaches this far (ApiClient.mapError's own doc
        // comment: only when the endpoint method itself didn't already
        // intercept it as an idempotent-success case) is a genuine
        // conflict — ConflictResolver's job is only to notice that from
        // the message text and make it findable, not to decide a
        // winner; see that class's own header comment for why.
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
        // Everything else — NetworkFailure, a StateError from a
        // handler naming a real but temporary gap (see
        // sale_sync_handler.dart's product/customer serverId checks),
        // or any unexpected exception. Treated as transient: counts
        // toward the attempts threshold, and per Section 8's own
        // "don't hammer a dead server" reasoning, this run stops here
        // rather than attempting the remaining items — a fresh failure
        // that hasn't yet crossed the threshold is read as "the server
        // (or connection) is genuinely down right now," which applies
        // to every remaining item in this run, not just this one.
        final attempts = item.syncAttempts + 1;
        if (attempts >= maxAttemptsBeforeAttentionNeeded) {
          await _markAttentionNeeded(item.id, error: e.toString());
          // Only captured once the item actually stops being retried —
          // a single transient failure well below the threshold is the
          // normal, expected shape of "the network hiccuped," not
          // something worth a permanent diagnostic record (brief
          // Section 14's "no excessive logging during normal
          // operation").
          unawaited(_captureSyncFailure(item: item, error: e, stackTrace: st));
        } else {
          await _recordAttempt(item.id, attempts: attempts, error: e.toString());
        }
        break;
      }
    }
  }

  /// Single capture point for every path above that ends in
  /// `attentionNeeded` — matches the brief's own example list item
  /// ("Sync failed / Remote record conflict / SyncService"). Severity is
  /// `warning`, not `error`: nothing here is lost (the write already
  /// succeeded locally and stays queued), so this is "needs a look," not
  /// "something broke."
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
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        syncAttempts: Value(attempts),
        lastError: Value(error),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }

  /// This same outcome — syncAttempts pinned at
  /// [maxAttemptsBeforeAttentionNeeded] — is reached two different ways:
  /// a business-rule-level rejection jumps straight here on its first
  /// occurrence (Architecture Section 5's point that retrying a 4xx can
  /// never fix it applies just as much at the queue level), while a
  /// transient failure only reaches it after repeatedly crossing the
  /// threshold across separate runs via [_recordAttempt]. Both are
  /// represented the same way in the schema — no separate status
  /// column, matching this codebase's own established preference for
  /// computed-over-stored state (e.g. Sale.balanceDue) — rather than a
  /// second field to track which path an item took to get here; the
  /// [error] text itself is what actually distinguishes them for anyone
  /// reading it later.
  Future<void> _markAttentionNeeded(
    String id, {
    required String error,
  }) async {
    await (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        syncAttempts: Value(maxAttemptsBeforeAttentionNeeded),
        lastError: Value(error),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }
}
