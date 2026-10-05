import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/sync_cursor_store.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/core/notifications/notification_service.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  late AppDatabase db;
  late SyncConfig config;
  late _MockNotificationService notifications;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    config = await SyncConfig.load();
    notifications = _MockNotificationService();
  });

  tearDown(() async {
    await db.close();
  });

  test('does not advance last push time for an empty sync cycle', () async {
    final notifier = SyncStatusNotifier(
      db: db,
      syncConfig: config,
      notificationService: notifications,
      preferences: await SharedPreferences.getInstance(),
      cursorStore: SharedPreferencesSyncCursorStore(await SharedPreferences.getInstance()),
    );

    await notifier.recordPushSuccess(
      'business-1',
      hadOutboundWork: false,
    );

    expect(notifier.healthFor('business-1').lastPushAt, isNull);
  });

  test('records last push time after real outbound work is drained', () async {
    final queueRow = SyncQueueItemsCompanion.insert(
      id: 'operation-1',
      entityType: 'sale',
      entityLocalId: 'sale-1',
      operation: 'create',
      priority: 1,
      enqueuedAt: DateTime(2026, 9, 28),
    );
    await db.into(db.syncQueueItems).insert(queueRow);
    await (db.delete(db.syncQueueItems)
          ..where((q) => q.id.equals('operation-1')))
        .go();

    final notifier = SyncStatusNotifier(
      db: db,
      syncConfig: config,
      notificationService: notifications,
      preferences: await SharedPreferences.getInstance(),
    );

    await notifier.recordPushSuccess(
      'business-1',
      hadOutboundWork: true,
    );

    expect(notifier.healthFor('business-1').lastPushAt, isNotNull);
  });
}
