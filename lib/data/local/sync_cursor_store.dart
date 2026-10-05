import 'package:shared_preferences/shared_preferences.dart';

import 'database/database.dart';

/// Durable persistence boundary for cloud change-feed acknowledgement.
///
/// SQLite is the source of truth in production. SharedPreferences is retained
/// only as a one-time migration source for installations created before the
/// cursor was moved into the database.
abstract interface class SyncCursorStore {
  int cursorFor(String businessId);

  Future<bool> persistMonotonic(String businessId, int cursor);

  Future<void> setAuthoritative(String businessId, int cursor);

  Future<void> reset(String businessId);
}

/// SQLite-backed cursor store used by the production sync runtime.
class DatabaseSyncCursorStore implements SyncCursorStore {
  DatabaseSyncCursorStore(this._database);

  final AppDatabase Function() _database;
  final Map<String, int> _cache = <String, int>{};

  Future<void> initialize({
    SharedPreferences? legacyPreferences,
  }) async {
    final database = _database();
    final rows = await database.select(database.syncCursors).get();
    for (final row in rows) {
      _cache[row.businessId] = row.cursor;
    }

    if (legacyPreferences == null) return;

    final legacyKeys = legacyPreferences.getKeys()
        .where((key) => key.startsWith('fulus_sync_cursor_'))
        .toList(growable: false);

    for (final key in legacyKeys) {
      final businessId = key.substring('fulus_sync_cursor_'.length);
      if (businessId.isEmpty) continue;
      final legacyCursor = legacyPreferences.getInt(key);
      if (legacyCursor == null) continue;
      final current = _cache[businessId] ?? 0;
      if (legacyCursor > current) {
        await _write(businessId, legacyCursor);
      }
      await legacyPreferences.remove(key);
    }
  }

  @override
  int cursorFor(String businessId) => _cache[businessId] ?? 0;

  @override
  Future<bool> persistMonotonic(String businessId, int cursor) async {
    if (cursor < 0) {
      throw ArgumentError.value(cursor, 'cursor', 'must be non-negative');
    }
    if (cursorFor(businessId) >= cursor) return true;
    await _write(businessId, cursor);
    return true;
  }

  @override
  Future<void> setAuthoritative(String businessId, int cursor) async {
    if (cursor < 0) {
      throw ArgumentError.value(cursor, 'cursor', 'must be non-negative');
    }
    await _write(businessId, cursor);
  }

  @override
  Future<void> reset(String businessId) async {
    final database = _database();
    await (database.delete(database.syncCursors)
          ..where((row) => row.businessId.equals(businessId)))
        .go();
    _cache.remove(businessId);
  }

  Future<void> _write(String businessId, int cursor) async {
    final database = _database();
    await database.into(database.syncCursors).insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            businessId: businessId,
            cursor: cursor,
          ),
        );
    _cache[businessId] = cursor;
  }
}

/// Test/legacy adapter preserving the previous preference-backed contract.
class SharedPreferencesSyncCursorStore implements SyncCursorStore {
  SharedPreferencesSyncCursorStore(this._preferences);

  final SharedPreferences _preferences;

  static String _key(String businessId) => 'fulus_sync_cursor_$businessId';

  @override
  int cursorFor(String businessId) => _preferences.getInt(_key(businessId)) ?? 0;

  @override
  Future<bool> persistMonotonic(String businessId, int cursor) async {
    if (cursorFor(businessId) >= cursor) return true;
    return _preferences.setInt(_key(businessId), cursor);
  }

  @override
  Future<void> setAuthoritative(String businessId, int cursor) async {
    final saved = await _preferences.setInt(_key(businessId), cursor);
    if (!saved) {
      throw StateError('Failed to persist the Cloud Sync cursor.');
    }
  }

  @override
  Future<void> reset(String businessId) async {
    final key = _key(businessId);
    final removed = await _preferences.remove(key);
    if (!removed && _preferences.containsKey(key)) {
      throw StateError('Failed to reset the Cloud Sync cursor.');
    }
  }
}
