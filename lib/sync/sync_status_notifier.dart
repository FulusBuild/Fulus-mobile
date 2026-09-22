import 'package:shared_preferences/shared_preferences.dart';

import '../core/notifications/notification_service.dart';
import '../data/local/database/database.dart';
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
    this.attentionThreshold = defaultSyncAttentionThreshold,
  })  : _db = db,
        _syncConfig = syncConfig,
        _notificationService = notificationService,
        _preferences = preferences;

  final AppDatabase _db;
  final SyncConfig _syncConfig;
  final NotificationService _notificationService;
  final SharedPreferences _preferences;
  final int attentionThreshold;

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
  static String _cursorKey(String businessId) => 'fulus_sync_cursor_$businessId';
  static String _recoveryKey(String businessId) => 'fulus_sync_recovery_$businessId';
  static String _recoveryErrorKey(String businessId) => 'fulus_sync_recovery_error_$businessId';

  SyncHealthSnapshot healthFor(String businessId) => SyncHealthSnapshot(
        lastPushAt: _readDate(_preferences.getString(_pushKey(businessId))),
        lastPullAt: _readDate(_preferences.getString(_pullKey(businessId))),
        cursor: _preferences.getInt(_cursorKey(businessId)) ?? 0,
        recoveryState: _preferences.getString(_recoveryKey(businessId)) ?? 'idle',
        lastError: _preferences.getString(_recoveryErrorKey(businessId)),
      );

  Future<void> markRecoveryStarted(String businessId) async {
    await _preferences.setString(_recoveryKey(businessId), 'recovering');
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  /// Records the authoritative restore boundary while recovery is still
  /// reconciling. Sync is not considered fully recovered until the
  /// post-bootstrap delta pull succeeds.
  Future<void> markRecoveryBoundaryPersisted(String businessId, int boundary) async {
    await _preferences.setInt(_cursorKey(businessId), boundary);
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  /// Marks stale-cursor recovery fully reconciled after the post-bootstrap
  /// delta pull has completed successfully.
  Future<void> markRecoveryCompleted(String businessId) async {
    await _preferences.setString(_recoveryKey(businessId), 'idle');
    await _preferences.remove(_recoveryErrorKey(businessId));
  }

  Future<void> markRecoveryFailed(String businessId, Object error) async {
    await _preferences.setString(_recoveryKey(businessId), 'blocked');
    await _preferences.setString(_recoveryErrorKey(businessId), error.toString());
  }

  Future<int> unresolvedConflictCount() async {
    final rows = await (_db.select(_db.syncConflictRecords)
          ..where((c) => c.resolvedAt.isNull()))
        .get();
    return rows.length;
  }

  Future<void> recordPushSuccess(String businessId) async {
    await _preferences.setString(_pushKey(businessId), DateTime.now().toUtc().toIso8601String());
  }

  Future<void> recordPullSuccess(String businessId, int cursor) async {
    await _preferences.setString(_pullKey(businessId), DateTime.now().toUtc().toIso8601String());
    await _preferences.setInt(_cursorKey(businessId), cursor);
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
  Future<void> checkForStuckSyncAndNotify() async {
    if (!_syncConfig.isEnabled) return;

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
