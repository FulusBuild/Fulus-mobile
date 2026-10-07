import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/sync_cursor_store.dart';

void main() {
  late AppDatabase db;
  late DatabaseSyncCursorStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = DatabaseSyncCursorStore(() => db);
  });

  tearDown(() async {
    await db.close();
  });

  test('persists and reads business cursors from SQLite', () async {
    await store.initialize();

    expect(store.cursorFor('business-1'), 0);

    await store.persistMonotonic('business-1', 7);
    expect(store.cursorFor('business-1'), 7);

    final rows = await db.select(db.syncCursors).get();
    expect(rows.single.businessId, 'business-1');
    expect(rows.single.cursor, 7);
  });

  test('durable cursor refresh sees another runtime advancing SQLite', () async {
    await store.initialize();
    await store.persistMonotonic('business-1', 5);

    await db.customStatement(
      "UPDATE sync_cursors SET cursor = 12 WHERE business_id = 'business-1'",
    );

    expect(store.cursorFor('business-1'), 5);
    expect(await store.durableCursorFor('business-1'), 12);
    expect(store.cursorFor('business-1'), 12);
  });

  test('monotonic persistence never moves a cursor backwards', () async {
    await store.initialize();

    await store.persistMonotonic('business-1', 10);
    await store.persistMonotonic('business-1', 4);

    expect(store.cursorFor('business-1'), 10);
  });

  test('legacy SharedPreferences cursors migrate into SQLite', () async {
    SharedPreferences.setMockInitialValues({
      'fulus_sync_cursor_business-1': 12,
      'fulus_sync_cursor_business-2': 3,
    });
    final preferences = await SharedPreferences.getInstance();

    await store.initialize(legacyPreferences: preferences);

    expect(store.cursorFor('business-1'), 12);
    expect(store.cursorFor('business-2'), 3);
    expect(preferences.getInt('fulus_sync_cursor_business-1'), isNull);
    expect(preferences.getInt('fulus_sync_cursor_business-2'), isNull);
  });

  test('authoritative restore boundary can replace an existing cursor', () async {
    await store.initialize();
    await store.persistMonotonic('business-1', 20);

    await store.setAuthoritative('business-1', 8);

    expect(store.cursorFor('business-1'), 8);
  });

  test('reset removes only the selected business cursor', () async {
    await store.initialize();
    await store.persistMonotonic('business-1', 8);
    await store.persistMonotonic('business-2', 9);

    await store.reset('business-1');

    expect(store.cursorFor('business-1'), 0);
    expect(store.cursorFor('business-2'), 9);
  });
  test('persists canonical block state without changing the durable cursor', () async {
    await store.initialize();
    await store.persistMonotonic('business-1', 17);

    final now = DateTime.utc(2026, 1, 2);
    await store.recordBlockedChange(
      businessId: 'business-1',
      change: SyncBlockedChange(
        sequence: 18,
        changeId: '18:sale:s18:upsert',
        entityType: 'sale',
        entityId: 's18',
        operation: 'upsert',
        firstSeenAt: now,
        lastAttemptedAt: now,
        attemptCount: 3,
        errorCode: 'validation',
        errorMessage: 'canonical payload is invalid',
      ),
    );

    expect(store.cursorFor('business-1'), 17);
    expect(store.blockedChangeFor('business-1')!.sequence, 18);

    final reloaded = DatabaseSyncCursorStore(() => db);
    await reloaded.initialize();

    expect(reloaded.cursorFor('business-1'), 17);
    final persisted = reloaded.blockedChangeFor('business-1')!;
    expect(persisted.attemptCount, 3);
    expect(persisted.errorMessage, 'canonical payload is invalid');
    expect(persisted.firstSeenAt, now);
    expect(persisted.lastAttemptedAt, now);
  });

  test('repairs blocked timestamps written as milliseconds by older builds', () async {
    final expected = DateTime.utc(2026, 10, 7, 21, 58, 50);
    final legacyMilliseconds = expected.millisecondsSinceEpoch;

    await db.customStatement(
      'INSERT INTO sync_cursors '
      '(business_id, cursor, blocked_sequence, blocked_change_id, '
      'blocked_entity_type, blocked_entity_id, blocked_operation, '
      'blocked_first_seen_at, blocked_last_attempted_at, blocked_attempt_count, '
      'blocked_error_code, blocked_error_message) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'business-1',
        17,
        18,
        '18:sale:s18:upsert',
        'sale',
        's18',
        'upsert',
        legacyMilliseconds,
        legacyMilliseconds,
        5,
        'validation',
        'canonical apply failed',
      ],
    );

    await store.initialize();

    final repaired = store.blockedChangeFor('business-1')!;
    expect(repaired.firstSeenAt, expected);
    expect(repaired.lastAttemptedAt, expected);

    final row = await (db.select(db.syncCursors)
          ..where((item) => item.businessId.equals('business-1')))
        .getSingle();
    expect(row.blockedFirstSeenAt?.millisecondsSinceEpoch, expected.millisecondsSinceEpoch);
    expect(row.blockedLastAttemptedAt?.millisecondsSinceEpoch, expected.millisecondsSinceEpoch);
  });

  test('stores blocked DateTime values in Drift-compatible timestamp units', () async {
    await store.initialize();
    final firstSeen = DateTime.utc(2026, 10, 7, 21, 58, 50);
    final lastAttempted = DateTime.utc(2026, 10, 7, 22, 0, 12);

    await store.recordBlockedChange(
      businessId: 'business-1',
      change: SyncBlockedChange(
        sequence: 10789,
        changeId: '10789:stock_movement:movement:upsert',
        entityType: 'stock_movement',
        entityId: 'movement',
        operation: 'upsert',
        firstSeenAt: firstSeen,
        lastAttemptedAt: lastAttempted,
        attemptCount: 1,
        errorCode: 'validation',
        errorMessage: 'canonical apply failed',
      ),
    );

    final reloaded = DatabaseSyncCursorStore(() => db);
    await reloaded.initialize();
    final persisted = reloaded.blockedChangeFor('business-1')!;

    expect(persisted.firstSeenAt.millisecondsSinceEpoch, firstSeen.millisecondsSinceEpoch);
    expect(persisted.lastAttemptedAt.millisecondsSinceEpoch, lastAttempted.millisecondsSinceEpoch);
  });

}
