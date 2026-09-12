import 'package:shared_preferences/shared_preferences.dart';

import 'fulus_sync_api.dart';

/// Phase 5 coordinator: owns the server change cursor and delegates
/// application of changes to the local repositories. It never makes local
/// business writes dependent on network availability.
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
      for (final change in page.changes) {
        // Apply each change before advancing the durable cursor. If the
        // process dies here, the same change is replayed; repository-level
        // upserts must therefore be idempotent.
        await _applyChange(change);
        cursor = change.sequence;
        await _preferences.setInt(_cursorKey(businessId), cursor);
      }
      if (!page.hasMore || page.changes.isEmpty) return cursor;
      if (page.nextCursor <= cursor) return cursor;
      cursor = page.nextCursor;
      await _preferences.setInt(_cursorKey(businessId), cursor);
    }
  }

  Future<void> resetCursor(String businessId) =>
      _preferences.remove(_cursorKey(businessId));
}
