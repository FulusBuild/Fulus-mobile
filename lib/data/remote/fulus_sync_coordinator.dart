import '../local/sync_cursor_store.dart';
import 'fulus_sync_api.dart';

/// Owns the durable server change cursor and applies server changes before
/// advancing that cursor. A process death can therefore replay a change, but
/// can never skip an unapplied change.
class FulusSyncCoordinator {
  FulusSyncCoordinator({
    required FulusSyncApi api,
    required SyncCursorStore cursorStore,
    required Future<void> Function(FulusSyncChange change) applyChange,
    Future<void> Function(List<FulusSyncChange> changes)? applyChanges,
    Future<bool> Function(FulusSyncChange change)? shouldApplyChange,
    Future<void> Function(Future<void> Function() action)? withApplyTransaction,
    Future<Object> Function(List<FulusSyncChange> changes)? prepareChanges,
    Future<void> Function(Object preparedChanges, List<FulusSyncChange> applicable)? applyPreparedChanges,
    Future<bool> Function(String businessId, int cursor)? persistCursor,
  })  : _api = api,
        _cursorStore = cursorStore,
        _applyChange = applyChange,
        _applyChanges = applyChanges,
        _shouldApplyChange = shouldApplyChange,
        _withApplyTransaction = withApplyTransaction,
        _prepareChanges = prepareChanges,
        _applyPreparedChanges = applyPreparedChanges,
        _persistCursorOverride = persistCursor;

  final FulusSyncApi _api;
  final SyncCursorStore _cursorStore;
  final Future<void> Function(FulusSyncChange change) _applyChange;
  final Future<void> Function(List<FulusSyncChange> changes)? _applyChanges;
  final Future<bool> Function(FulusSyncChange change)? _shouldApplyChange;
  final Future<void> Function(Future<void> Function() action)? _withApplyTransaction;
  final Future<Object> Function(List<FulusSyncChange> changes)? _prepareChanges;
  final Future<void> Function(Object preparedChanges, List<FulusSyncChange> applicable)? _applyPreparedChanges;
  final Future<bool> Function(String businessId, int cursor)? _persistCursorOverride;

  int cursorFor(String businessId) => _cursorStore.cursorFor(businessId);

  Future<int> pullAndApply({
    required String businessId,
    int batchSize = 100,
  }) async {
    var cursor = cursorFor(businessId);
    while (true) {
      // Another runtime may have completed a newer pull while this runtime
      // was suspended. Never issue a request from a stale cursor when the
      // durable acknowledgement has already advanced.
      cursor = _maxCursor(cursor, cursorFor(businessId));
      final page = await _api.pullChanges(
        businessId: businessId,
        cursor: cursor,
        limit: batchSize,
      );
      // Another runtime may have completed a newer pull while this request
      // was in flight. Refresh the durable acknowledgement before deciding
      // which returned changes are still eligible for local reconciliation.
      // Otherwise a stale runtime could reapply a page that a newer runtime
      // has already acknowledged.
      cursor = _maxCursor(cursor, cursorFor(businessId));
      if (page.changes.isEmpty) {
        if (page.hasMore) {
          throw StateError(
            'Cloud Sync returned an empty page while reporting more changes.',
          );
        }
        return cursor;
      }

      if (page.cursor > cursor) {
        throw StateError(
          'Cloud Sync response cursor is ahead of the requested cursor.',
        );
      }
      final unapplied = page.changes.where((change) => change.sequence > cursor).toList(growable: false);
      if (unapplied.isNotEmpty) {
        // The server change sequence is global, while the pull is filtered to
        // this business. Therefore legitimate global sequence gaps are expected
        // (other businesses may own the missing sequences). What must never
        // happen is a reordered page: acknowledging a later sequence before an
        // earlier returned change could permanently skip that earlier change.
        var previousSequence = cursor;
        for (final change in unapplied) {
          if (change.sequence <= previousSequence) {
            throw StateError(
              'Cloud Sync change feed is not ordered: expected a sequence '
              'greater than $previousSequence but received ${change.sequence}.',
            );
          }
          previousSequence = change.sequence;
        }
        final prepareChanges = _prepareChanges;
        final applyPreparedChanges = _applyPreparedChanges;
        final withApplyTransaction = _withApplyTransaction;

        if (prepareChanges != null || applyPreparedChanges != null) {
          if (prepareChanges == null || applyPreparedChanges == null) {
            throw StateError(
              'Prepared sync application requires both preparation and apply callbacks.',
            );
          }

          // Remote canonical reads must complete before the local write
          // transaction starts. Otherwise a slow network request keeps SQLite's
          // writer transaction open and blocks foreground local reads.
          final prepared = await prepareChanges(unapplied);
          final applyPreparedPage = () async {
            final applicable = <FulusSyncChange>[];
            for (final change in unapplied) {
              final shouldApply = _shouldApplyChange == null
                  ? true
                  : await _shouldApplyChange(change);
              if (shouldApply) applicable.add(change);
            }
            if (applicable.isNotEmpty) {
              await applyPreparedChanges(prepared, applicable);
            }
          };
          if (withApplyTransaction != null) {
            // The transaction now contains only the final eligibility check and
            // local writes. This preserves OCC/lease fencing without holding the
            // SQLite writer lock across network I/O.
            await withApplyTransaction(applyPreparedPage);
          } else {
            await applyPreparedPage();
          }
        } else {
          final applyPage = () async {
            final applicable = <FulusSyncChange>[];
            for (final change in unapplied) {
              final shouldApply = _shouldApplyChange == null
                  ? true
                  : await _shouldApplyChange(change);
              if (shouldApply) applicable.add(change);
            }
            final applyChanges = _applyChanges;
            if (applyChanges != null && applicable.isNotEmpty) {
              await applyChanges(applicable);
            } else {
              for (final change in applicable) {
                // Apply first, persist cursor second. Replaying a successfully applied
                // change after a crash is safe because reconciliation is idempotent.
                await _applyChange(change);
              }
            }
          };
          if (withApplyTransaction != null) {
            await withApplyTransaction(applyPage);
          } else {
            await applyPage();
          }
        }
        // A change intentionally held behind a pending local mutation is still
        // acknowledged in the feed. Its authoritative state is recovered by
        // the eventual push result or explicit conflict resolution. Leaving the
        // cursor behind would replay the same remote change forever and could
        // starve later changes.
        for (final change in unapplied) {
          cursor = _maxCursor(cursor, change.sequence);
          await _persistCursor(businessId, cursor);
        }
        cursor = _maxCursor(cursor, cursorFor(businessId));
      }

      if (!page.hasMore) return cursor;
      if (unapplied.isEmpty) {
        final durableCursor = cursorFor(businessId);
        if (durableCursor > cursor) {
          cursor = durableCursor;
          continue;
        }
        throw StateError(
          'Cloud Sync returned a page with no forward progress while reporting more changes.',
        );
      }
      // page.nextCursor is only a pagination hint. Never persist it as an
      // acknowledgement because a process could have died before applying
      // one of the returned changes.
    }
  }

  /// Sets the acknowledged cursor to an authoritative restore snapshot boundary.
  /// The bootstrap transaction must commit before this is called; after it
  /// succeeds, the next pull starts strictly after the snapshot boundary.
  Future<void> setCursor(String businessId, int cursor) async {
    if (cursor < 0) {
      throw ArgumentError.value(cursor, 'cursor', 'must be non-negative');
    }
    if (_persistCursorOverride != null) {
      final persisted = await _persistCursorOverride(businessId, cursor);
      if (!persisted) {
        throw StateError('Failed to persist the Cloud Sync snapshot boundary cursor.');
      }
      return;
    }
    await _cursorStore.setAuthoritative(businessId, cursor);
  }

  Future<void> _persistCursor(String businessId, int cursor) async {
    // SharedPreferences is not transactional across runtimes. Make the
    // acknowledgement monotonic so an older suspended pull can never move a
    // newer durable cursor backwards after another runtime has progressed.
    if (_persistCursorOverride != null) {
      final current = cursorFor(businessId);
      if (current >= cursor) return;
      final persisted = await _persistCursorOverride(businessId, cursor);
      if (!persisted) {
        throw StateError('Failed to persist the Cloud Sync cursor.');
      }
      return;
    }
    await _cursorStore.persistMonotonic(businessId, cursor);
  }

  int _maxCursor(int a, int b) => a >= b ? a : b;

  Future<void> resetCursor(String businessId) => _cursorStore.reset(businessId);
}
