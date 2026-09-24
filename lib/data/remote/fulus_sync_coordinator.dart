import 'package:shared_preferences/shared_preferences.dart';

import 'fulus_sync_api.dart';

/// Owns the durable server change cursor and applies server changes before
/// advancing that cursor. A process death can therefore replay a change, but
/// can never skip an unapplied change.
class FulusSyncCoordinator {
  FulusSyncCoordinator({
    required FulusSyncApi api,
    required SharedPreferences preferences,
    required Future<void> Function(FulusSyncChange change) applyChange,
    Future<void> Function(List<FulusSyncChange> changes)? applyChanges,
    Future<bool> Function(FulusSyncChange change)? shouldApplyChange,
    Future<void> Function(Future<void> Function() action)? withApplyTransaction,
  })  : _api = api,
        _preferences = preferences,
        _applyChange = applyChange,
        _applyChanges = applyChanges,
        _shouldApplyChange = shouldApplyChange,
        _withApplyTransaction = withApplyTransaction;

  final FulusSyncApi _api;
  final SharedPreferences _preferences;
  final Future<void> Function(FulusSyncChange change) _applyChange;
  final Future<void> Function(List<FulusSyncChange> changes)? _applyChanges;
  final Future<bool> Function(FulusSyncChange change)? _shouldApplyChange;
  final Future<void> Function(Future<void> Function() action)? _withApplyTransaction;

  static String _cursorKey(String businessId) => 'fulus_sync_cursor_$businessId';

  int cursorFor(String businessId) =>
      _preferences.getInt(_cursorKey(businessId)) ?? 0;

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
        final withApplyTransaction = _withApplyTransaction;
        if (withApplyTransaction != null) {
          // Keep the eligibility check and local reconciliation in one Drift
          // transaction. Drift starts native SQLite transactions as write
          // transactions, so another runtime cannot commit a local write between
          // the eligibility check and canonical reconciliation. Its write waits
          // for this short transaction instead of being allowed to interleave.
          await withApplyTransaction(applyPage);
        } else {
          await applyPage();
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
    final persisted = await _preferences.setInt(_cursorKey(businessId), cursor);
    if (!persisted) {
      throw StateError('Failed to persist the Cloud Sync snapshot boundary cursor.');
    }
  }

  Future<void> _persistCursor(String businessId, int cursor) async {
    // SharedPreferences is not transactional across runtimes. Make the
    // acknowledgement monotonic so an older suspended pull can never move a
    // newer durable cursor backwards after another runtime has progressed.
    final current = cursorFor(businessId);
    if (current >= cursor) return;
    final persisted = await _preferences.setInt(_cursorKey(businessId), cursor);
    if (!persisted) {
      throw StateError('Failed to persist the Cloud Sync cursor.');
    }
  }

  int _maxCursor(int a, int b) => a >= b ? a : b;

  Future<void> resetCursor(String businessId) async {
    final removed = await _preferences.remove(_cursorKey(businessId));
    if (!removed && _preferences.containsKey(_cursorKey(businessId))) {
      throw StateError('Failed to reset the Cloud Sync cursor.');
    }
  }
}
