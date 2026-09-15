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
  })  : _api = api,
        _preferences = preferences,
        _applyChange = applyChange;

  final FulusSyncApi _api;
  final SharedPreferences _preferences;
  final Future<void> Function(FulusSyncChange change) _applyChange;

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
      if (page.changes.isEmpty) return cursor;

      for (final change in page.changes) {
        if (change.sequence <= cursor) continue;
        // Apply first, persist cursor second. Replaying a successfully applied
        // change after a crash is safe because reconciliation is idempotent;
        // skipping an unapplied change is never safe.
        await _applyChange(change);
        cursor = change.sequence;
        await _preferences.setInt(_cursorKey(businessId), cursor);
      }

      if (!page.hasMore) return cursor;
      // page.nextCursor is only a pagination hint. Never persist it as an
      // acknowledgement because a process could have died before applying
      // one of the returned changes.
    }
  }

  Future<void> resetCursor(String businessId) =>
      _preferences.remove(_cursorKey(businessId));
}
