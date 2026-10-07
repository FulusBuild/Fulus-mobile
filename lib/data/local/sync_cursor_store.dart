import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/database.dart';

/// Durable persistence boundary for cloud change-feed acknowledgement.
///
/// SQLite is the source of truth in production. SharedPreferences is retained
/// only as a one-time migration source for installations created before the
/// cursor was moved into the database.
abstract interface class SyncCursorStore {
  int cursorFor(String businessId);

  SyncBlockedChange? blockedChangeFor(String businessId);

  Future<void> recordBlockedChange({
    required String businessId,
    required SyncBlockedChange change,
  });

  Future<void> clearBlockedChange(String businessId);

  Future<bool> persistMonotonic(String businessId, int cursor);

  Future<void> setAuthoritative(String businessId, int cursor);

  Future<void> reset(String businessId);
}

/// Durable evidence that canonical application is blocked at the current
/// cursor boundary. A blocked change is never an acknowledgement or a skip.
class SyncBlockedChange {
  const SyncBlockedChange({
    required this.sequence,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.firstSeenAt,
    required this.lastAttemptedAt,
    required this.attemptCount,
    required this.errorCode,
    required this.errorMessage,
  });

  final int sequence;
  final String changeId;
  final String entityType;
  final String entityId;
  final String operation;
  final DateTime firstSeenAt;
  final DateTime lastAttemptedAt;
  final int attemptCount;
  final String? errorCode;
  final String errorMessage;
}

/// SQLite-backed cursor store used by the production sync runtime.
class DatabaseSyncCursorStore implements SyncCursorStore {
  DatabaseSyncCursorStore(this._database);

  final AppDatabase Function() _database;
  final Map<String, int> _cache = <String, int>{};
  final Map<String, SyncBlockedChange?> _blockedCache = <String, SyncBlockedChange?>{};

  Future<void> initialize({
    SharedPreferences? legacyPreferences,
  }) async {
    final database = _database();
    final rows = await database.select(database.syncCursors).get();
    for (final row in rows) {
      _cache[row.businessId] = row.cursor;
      _blockedCache[row.businessId] = row.blockedSequence == null
          ? null
          : SyncBlockedChange(
              sequence: row.blockedSequence!,
              changeId: row.blockedChangeId ?? '',
              entityType: row.blockedEntityType ?? '',
              entityId: row.blockedEntityId ?? '',
              operation: row.blockedOperation ?? '',
              firstSeenAt: row.blockedFirstSeenAt ?? DateTime.now().toUtc(),
              lastAttemptedAt: row.blockedLastAttemptedAt ?? DateTime.now().toUtc(),
              attemptCount: row.blockedAttemptCount,
              errorCode: row.blockedErrorCode,
              errorMessage: row.blockedErrorMessage ?? 'Unknown canonical apply failure.',
            );
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
  SyncBlockedChange? blockedChangeFor(String businessId) =>
      _blockedCache[businessId];

  @override
  Future<void> recordBlockedChange({
    required String businessId,
    required SyncBlockedChange change,
  }) async {
    final database = _database();
    await database.customStatement(
      'INSERT INTO sync_cursors '
      '(business_id, cursor, blocked_sequence, blocked_change_id, '
      'blocked_entity_type, blocked_entity_id, blocked_operation, '
      'blocked_first_seen_at, blocked_last_attempted_at, blocked_attempt_count, '
      'blocked_error_code, blocked_error_message) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(business_id) DO UPDATE SET '
      'blocked_sequence = excluded.blocked_sequence, '
      'blocked_change_id = excluded.blocked_change_id, '
      'blocked_entity_type = excluded.blocked_entity_type, '
      'blocked_entity_id = excluded.blocked_entity_id, '
      'blocked_operation = excluded.blocked_operation, '
      'blocked_first_seen_at = excluded.blocked_first_seen_at, '
      'blocked_last_attempted_at = excluded.blocked_last_attempted_at, '
      'blocked_attempt_count = excluded.blocked_attempt_count, '
      'blocked_error_code = excluded.blocked_error_code, '
      'blocked_error_message = excluded.blocked_error_message',
      [
        businessId,
        cursorFor(businessId),
        change.sequence,
        change.changeId,
        change.entityType,
        change.entityId,
        change.operation,
        change.firstSeenAt.millisecondsSinceEpoch,
        change.lastAttemptedAt.millisecondsSinceEpoch,
        change.attemptCount,
        change.errorCode,
        change.errorMessage,
      ],
    );
    _blockedCache[businessId] = change;
  }

  @override
  Future<void> clearBlockedChange(String businessId) async {
    final database = _database();
    await (database.update(database.syncCursors)
          ..where((row) => row.businessId.equals(businessId)))
        .write(
      const SyncCursorsCompanion(
        blockedSequence: Value(null),
        blockedChangeId: Value(null),
        blockedEntityType: Value(null),
        blockedEntityId: Value(null),
        blockedOperation: Value(null),
        blockedFirstSeenAt: Value(null),
        blockedLastAttemptedAt: Value(null),
        blockedAttemptCount: Value(0),
        blockedErrorCode: Value(null),
        blockedErrorMessage: Value(null),
      ),
    );
    _blockedCache[businessId] = null;
  }

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
    _blockedCache.remove(businessId);
  }

  int _max(int a, int b) => a >= b ? a : b;

  Future<void> _write(String businessId, int cursor) async {
    final database = _database();
    await database.customStatement(
      'INSERT INTO sync_cursors (business_id, cursor) VALUES (?, ?) '
      'ON CONFLICT(business_id) DO UPDATE SET '
      'cursor = MAX(sync_cursors.cursor, excluded.cursor)',
      [businessId, cursor],
    );
    _cache[businessId] = _max(_cache[businessId] ?? 0, cursor);
  }
}

/// Test/legacy adapter preserving the previous preference-backed contract.
class SharedPreferencesSyncCursorStore implements SyncCursorStore {
  SharedPreferencesSyncCursorStore(this._preferences);

  final SharedPreferences _preferences;

  static String _key(String businessId) => 'fulus_sync_cursor_$businessId';
  static String _blockedKey(String businessId) =>
      'fulus_sync_blocked_$businessId';

  @override
  int cursorFor(String businessId) => _preferences.getInt(_key(businessId)) ?? 0;

  @override
  SyncBlockedChange? blockedChangeFor(String businessId) {
    final raw = _preferences.getString(_blockedKey(businessId));
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return SyncBlockedChange(
      sequence: map['sequence'] as int,
      changeId: map['changeId'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      operation: map['operation'] as String,
      firstSeenAt: DateTime.parse(map['firstSeenAt'] as String),
      lastAttemptedAt: DateTime.parse(map['lastAttemptedAt'] as String),
      attemptCount: map['attemptCount'] as int,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String,
    );
  }

  @override
  Future<void> recordBlockedChange({
    required String businessId,
    required SyncBlockedChange change,
  }) async {
    final saved = await _preferences.setString(
      _blockedKey(businessId),
      jsonEncode({
        'sequence': change.sequence,
        'changeId': change.changeId,
        'entityType': change.entityType,
        'entityId': change.entityId,
        'operation': change.operation,
        'firstSeenAt': change.firstSeenAt.toUtc().toIso8601String(),
        'lastAttemptedAt': change.lastAttemptedAt.toUtc().toIso8601String(),
        'attemptCount': change.attemptCount,
        'errorCode': change.errorCode,
        'errorMessage': change.errorMessage,
      }),
    );
    if (!saved) throw StateError('Failed to persist the blocked canonical change.');
  }

  @override
  Future<void> clearBlockedChange(String businessId) async {
    final removed = await _preferences.remove(_blockedKey(businessId));
    if (!removed && _preferences.containsKey(_blockedKey(businessId))) {
      throw StateError('Failed to clear the blocked canonical change.');
    }
  }

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
    await clearBlockedChange(businessId);
  }
}
