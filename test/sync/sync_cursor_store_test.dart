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
    expect(reloaded.blockedChangeFor('business-1')!.attemptCount, 3);
    expect(reloaded.blockedChangeFor('business-1')!.errorMessage, 'canonical payload is invalid');
  });

}
