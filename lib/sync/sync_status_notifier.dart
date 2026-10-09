import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors/failure.dart';
import '../core/notifications/notification_service.dart';
import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';
import '../data/local/database/database.dart';
import '../data/local/sync_cursor_store.dart';
import 'sync_config.dart';
import 'sync_status.dart';

/// The threshold both [SyncEngine] and this class need to agree on for
/// "how many failed attempts before an item counts as needing
/// attention." Lives here, as a single named constant, specifically so
/// bootstrap.dart can pass the SAME value into both constructors
/// (SyncEngine.maxAttemptsBeforeAttentionNeeded already defaults to 5
/// inline — this doesn't change that file, it just gives the number a
/// name a second class can reference too, rather than that second class
/// silently duplicating the literal `5` and risking the two drifting
/// apart if one is ever tuned without the other).
const int defaultSyncAttentionThreshold = 5;

/// Fills in the architecture document's own named-but-missing piece —
/// Section 1's folder structure lists `sync/sync_status_notifier.dart`
/// ("Feeds the persistent indicator, Volume 2/Volume 12") as an intended
/// file; it didn't exist in the checkpoint this stage started from. Two
/// jobs, both squarely "sync layer, not another stage's business logic":
///
/// 1. [watch] — the reactive `Stream<SyncStatus>` a future sync
///    indicator widget (Volume 2, visible on every screen) and Settings'
///    sync detail screen (Volume 11) both need, built on Drift's
///    `.watch()` exactly as Architecture Section 2 describes for
///    exactly this kind of "changes from outside the widget tree" case.
/// 2. [checkForStuckSyncAndNotify] — Volume 12 Decision 43's second
///    notification trigger ("pending data that's stayed unsynced for an
///    unusually long time despite the device showing as online"),
///    called from sync_triggers.dart after every automatic or manual
///    drain attempt.
///
/// What this class deliberately does NOT do: decide when a drain
/// attempt happens (sync_triggers.dart), run the drain itself
/// (sync_engine.dart), or resolve conflicts (sync_conflict_resolver.dart). This is a
/// read-model over state those other classes already produce, plus one
/// small piece of judgment (has this been stuck long enough, and have I
/// already said so) layered on top.
class SyncStatusNotifier {
  SyncStatusNotifier({
    required AppDatabase db,
    required SyncConfig syncConfig,
    required NotificationService notificationService,
    required SharedPreferences preferences,
    required SyncCursorStore cursorStore,
    DiagnosticLogger? diagnosticLogger,
    this.attentionThreshold = defaultSyncAttentionThreshold,
  })  : _db = db,
        _syncConfig = syncConfig,
        _notificationService = notificationService,
        _preferences = preferences,
        _cursorStore = cursorStore,
        _diagnosticLogger = diagnosticLogger;

  final AppDatabase _db;
  final SyncConfig _syncConfig;
  final NotificationService _notificationService;
  final SharedPreferences _preferences;
  final SyncCursorStore _cursorStore;
  final int attentionThreshold;
  final DiagnosticLogger? _diagnosticLogger;
  DateTime? _lastHealthEmissionAt;

  /// Tracks whether the current "stuck" episode has already produced a
  /// notification — in-memory only, deliberately not persisted. A
  /// single SyncStatusNotifier instance lives for the whole app process
  /// (constructed once in bootstrap.dart, the same "never
  /// re-instantiated per screen" discipline SyncEngine's own doc
  /// comment states), so in-memory state here survives exactly as long
  /// as it needs to: reset the moment the queue genuinely drains below
  /// the threshold, so a LATER, separate stuck episode still notifies
  /// again rather than being silently suppressed forever by an episode
  /// that resolved hours or days earlier.
  bool _alreadyNotifiedForCurrentEpisode = false;

  static String _pushKey(String businessId) => 'fulus_sync_last_push_$businessId';
  static String _pullKey(String businessId) => 'fulus_sync_last_pull_$businessId';
  static String _recoveryKey(String businessId) => 'fulus_sync_recovery_$businessId';
  static String _recoveryErrorKey(String businessId) => 'fulus_sync_recovery_error_$businessId';
  static String _recoveryStartedKey(String businessId) => 'fulus_sync_recovery_started_$businessId';
  static String _recoveryDurationKey(String businessId) => 'fulus_sync_recovery_duration_ms_$businessId';

  SyncHealthSnapshot healthFor(String businessId) => SyncHealthSnapshot(
        lastPushAt: _readDate(_preferences.getString(_pushKey(businessId))),
        lastPullAt: _readDate(_preferences.getString(_pullKey(businessId))),
        cursor: _cursorStore.cursorFor(businessId),
        recoveryState: _preferences.getString(_recoveryKey(businessId)) ?? 'idle',
        lastError: _preferences.getString(_recoveryErrorKey(businessId)),
      );

  Future<void> markRecoveryStarted(String businessId) async {
    await _preferences.setString(_recoveryKey(businessId), 'recovering');
    await _preferences.setString(_recoveryStartedKey(businessId), DateTime.now().toUtc().toIso8601String());
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  /// Clears persisted sync-health metadata before an authoritative local
  /// restore. The restored snapshot is a new local dataset, so a cursor,
  /// push/pull timestamps, or a previous recovery failure from the old
  /// dataset must not be presented as the health of the restored business.
  Future<void> resetForAuthoritativeRestore(String businessId) async {
    await _preferences.remove(_pushKey(businessId));
    await _preferences.remove(_pullKey(businessId));
    await _cursorStore.reset(businessId);
    await _preferences.setString(_recoveryKey(businessId), 'idle');
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  /// Records the authoritative restore boundary while recovery is still
  /// reconciling. Sync is not considered fully recovered until the
  /// post-bootstrap delta pull succeeds.
  Future<void> markRecoveryBoundaryPersisted(String businessId, int boundary) async {
    await _cursorStore.setAuthoritative(businessId, boundary);
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  /// Marks stale-cursor recovery fully reconciled after the post-bootstrap
  /// delta pull has completed successfully.
  Future<void> markRecoveryCompleted(String businessId) async {
    final started = _readDate(_preferences.getString(_recoveryStartedKey(businessId)));
    if (started != null) {
      await _preferences.setInt(_recoveryDurationKey(businessId), DateTime.now().toUtc().difference(started).inMilliseconds);
    }
    await _preferences.remove(_recoveryStartedKey(businessId));
    await _preferences.setString(_recoveryKey(businessId), 'idle');
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  Future<void> markRecoveryFailed(String businessId, Object error) async {
    final started = _readDate(_preferences.getString(_recoveryStartedKey(businessId)));
    if (started != null) {
      await _preferences.setInt(_recoveryDurationKey(businessId), DateTime.now().toUtc().difference(started).inMilliseconds);
    }
    await _preferences.remove(_recoveryStartedKey(businessId));
    await _preferences.setString(_recoveryKey(businessId), 'blocked');
    final message = error is Failure ? error.message : error.toString();
    await _preferences.setString(_recoveryErrorKey(businessId), message);
  }

  Future<int> unresolvedConflictCount() async {
    final rows = await (_db.select(_db.syncConflictRecords)
          ..where((c) => c.resolvedAt.isNull()))
        .get();
    return rows.length;
  }

  /// Records a successful outbound reconciliation only when the durable
  /// outbox is actually empty. SyncEngine deliberately returns normally when
  /// retryable or attention-needed items remain queued so independent work can
  /// continue; treating that normal return as a push success would make the
  /// UI report a backup that did not finish and can also make stale-cursor
  /// recovery appear mysteriously blocked by the same queued work.
  Future<void> recordPushSuccess(
    String businessId, {
    required bool hadOutboundWork,
  }) async {
    if (!hadOutboundWork) return;
    final pending = await _db.select(_db.syncQueueItems).get();
    if (pending.isNotEmpty) return;
    await _preferences.setString(
      _pushKey(businessId),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> recordPullSuccess(String businessId, int cursor) async {
    await _preferences.setString(_pullKey(businessId), DateTime.now().toUtc().toIso8601String());

  }

  static String _boundedDiagnosticText(String? value) {
    final normalized = (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '';
    return normalized.length <= 160 ? normalized : normalized.substring(0, 160);
  }

  DateTime? _readDate(String? raw) => raw == null ? null : DateTime.tryParse(raw);

  /// Evaluated once per call, not itself reactive to SyncConfig changing
  /// mid-stream — see SyncConfig's own doc comment on why enabling sync
  /// is already a restart-shaped action in this first pass, not a
  /// live-toggle one. A caller that flips the toggle and wants the
  /// indicator to reflect it immediately should re-subscribe (a screen
  /// rebuild does this naturally).
  Stream<SyncStatus> watch() async* {
    if (!_syncConfig.isEnabled) {
      yield const SyncStatus.disabled();
      return;
    }

    // Drift's watch query normally emits its initial result, but expose an
    // explicit first snapshot as well. The sync screen must never remain in
    // Riverpod's loading state simply because the database stream has not
    // produced its first event yet.
    final query = _db.select(_db.syncQueueItems);
    yield await _toStatus(await query.get());
    await for (final items in query.watch()) {
      yield await _toStatus(items);
    }
  }

  Future<SyncStatus> _toStatus(List<SyncQueueItem> items) async {
    final unresolvedConflicts = await (_db.select(_db.syncConflictRecords)
          ..where((c) => c.resolvedAt.isNull()))
        .get();
    final conflictCount = unresolvedConflicts.length;
    if (items.isEmpty && conflictCount == 0) return const SyncStatus.settled();

    final attentionCount =
        items.where((i) => i.syncAttempts >= attentionThreshold).length;

    if (attentionCount > 0) {
      return SyncStatus.attentionNeeded(
        attentionCount: attentionCount,
        pendingCount: items.length,
        conflictCount: conflictCount,
      );
    }

    // Deliberately not distinguishing "syncing right now" from "pending"
    // here — that distinction depends on SyncEngine's own in-flight
    // `_isRunning` flag (sync_engine.dart), which this class has no
    // reference to and shouldn't reach into just to report a transient
    // state the Bible itself calls "brief" and "not one the user needs
    // to wait on." A future pass wiring SyncEngine to expose that flag
    // reactively (e.g. via its own small stream) can upgrade this to a
    // true SyncStatus.syncing without this class's own shape changing.
    if (conflictCount > 0) {
      return SyncStatus.attentionNeeded(
        attentionCount: attentionCount,
        pendingCount: items.length,
        conflictCount: conflictCount,
      );
    }

    return SyncStatus.pending(items.length);
  }

  /// Called from sync_triggers.dart after every drain attempt
  /// (automatic or manual) — a one-shot check, not itself a stream,
  /// since "should I show a notification right now" is a point-in-time
  /// decision, not something UI needs to react to continuously the way
  /// [watch] is.
  Future<void> emitHealthDiagnostic(String businessId) async {
    final logger = _diagnosticLogger;
    if (logger == null) return;
    final now = DateTime.now().toUtc();
    final last = _lastHealthEmissionAt;
    if (last != null && now.difference(last) < const Duration(minutes: 15)) return;
    _lastHealthEmissionAt = now;

    final items = await _db.select(_db.syncQueueItems).get();
    final attention = items.where((item) => item.syncAttempts >= attentionThreshold).length;
    final oldest = items.isEmpty
        ? null
        : items.map((item) => item.enqueuedAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final blocked = await _cursorStore.blockedChangeFor(businessId);
    final lastPush = _readDate(_preferences.getString(_pushKey(businessId)));
    final lastPull = _readDate(_preferences.getString(_pullKey(businessId)));
    final recoveryState = _preferences.getString(_recoveryKey(businessId)) ?? 'idle';
    final recoveryDuration = _preferences.getInt(_recoveryDurationKey(businessId));
    final conflicts = await (_db.select(_db.syncConflictRecords)
          ..where((conflict) => conflict.resolvedAt.isNull()))
        .get();

    // Summary counts alone cannot identify why a device never reaches a
    // settled outbox. Include bounded, identifier-free item metadata so a
    // diagnostic export can distinguish a rejected upload from dependency
    // deferral, a stale business write, or an unresolved conflict. Do not
    // export local row IDs, actor IDs, or conflict messages (which may carry
    // user-entered business data).
    final diagnosticItems = items.toList()
      ..sort((a, b) {
        final attempts = b.syncAttempts.compareTo(a.syncAttempts);
        return attempts != 0 ? attempts : a.enqueuedAt.compareTo(b.enqueuedAt);
      });
    final itemDetails = diagnosticItems.take(8).map((item) => {
          'entity_type': item.entityType,
          'operation': item.operation,
          'priority': item.priority,
          'attempts': item.syncAttempts,
          'age_seconds': now.difference(item.enqueuedAt).inSeconds,
          'last_attempted_at': item.lastAttemptedAt?.toUtc().toIso8601String(),
          'last_error': _boundedDiagnosticText(item.lastError),
        }).toList();
    final conflictDetails = conflicts
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final conflictSummary = conflictDetails.take(8).map((conflict) => {
          'entity_type': conflict.entityType,
          'code': conflict.code,
          'age_seconds': now.difference(conflict.createdAt).inSeconds,
        }).toList();

    await logger.captureInfo(
      category: DiagnosticCategory.synchronization,
      title: 'Sync health',
      message: 'Periodic sync health snapshot.',
      technicalContext: {
        'pending_count': items.length.toString(),
        'attention_count': attention.toString(),
        'unresolved_conflict_count': conflicts.length.toString(),
        'oldest_pending_age_seconds': oldest == null ? '0' : now.difference(oldest).inSeconds.toString(),
        'max_attempts': items.isEmpty ? '0' : items.map((item) => item.syncAttempts).reduce((a, b) => a > b ? a : b).toString(),
        'blocked_count': blocked == null ? '0' : '1',
        'pending_items_json': jsonEncode(itemDetails),
        'unresolved_conflicts_json': jsonEncode(conflictSummary),
        'last_successful_push_at': lastPush?.toUtc().toIso8601String() ?? '',
        'last_successful_pull_at': lastPull?.toUtc().toIso8601String() ?? '',
        'last_restore_result': recoveryState,
        'last_restore_duration_ms': recoveryDuration?.toString() ?? '',
      },
    );
  }

  Future<void> checkForStuckSyncAndNotify() async {
    if (!_syncConfig.isEnabled) return;

    final businessId = _preferences.getString('fulus_local_cloud_business_id');
    if (businessId != null) await emitHealthDiagnostic(businessId);

    final items = await _db.select(_db.syncQueueItems).get();
    final attentionCount =
        items.where((i) => i.syncAttempts >= attentionThreshold).length;

    if (attentionCount == 0) {
      // Resolved (or never started) — re-arm for the next episode.
      _alreadyNotifiedForCurrentEpisode = false;
      return;
    }

    if (_alreadyNotifiedForCurrentEpisode) return;

    _alreadyNotifiedForCurrentEpisode = true;
    await _notificationService.notifyStuckSync(attentionCount: attentionCount);
  }
}
