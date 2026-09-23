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
  })  : _api = api,
        _preferences = preferences,
        _applyChange = applyChange,
        _applyChanges = applyChanges;

  final FulusSyncApi _api;
  final SharedPreferences _preferences;
  final Future<void> Function(FulusSyncChange change) _applyChange;
  final Future<void> Function(List<FulusSyncChange> changes)? _applyChanges;

  static String _cursorKey(String businessId) => 'fulus_sync_cursor_$businessId';

  int cursorFor(String businessId) =>
      _preferences.getInt(_cursorKey(businessId)) ?? 0;

  Future<int> pullAndApply({
    required String businessId,
    int batchSize = 100,
  }) async {
    var cursor = cursorFor(businessId);
    while (true) {
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
        final applyChanges = _applyChanges;
        if (applyChanges != null) {
          await applyChanges(unapplied);
          for (final change in unapplied) {
            cursor = change.sequence;
            await _preferences.setInt(_cursorKey(businessId), cursor);
          }
        } else {
          for (final change in unapplied) {
            // Apply first, persist cursor second. Replaying a successfully applied
            // change after a crash is safe because reconciliation is idempotent;
            // skipping an unapplied change is never safe.
            await _applyChange(change);
            cursor = change.sequence;
            await _preferences.setInt(_cursorKey(businessId), cursor);
          }
        }
      }

      if (!page.hasMore) return cursor;
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

  Future<void> resetCursor(String businessId) =>
      _preferences.remove(_cursorKey(businessId));
}
