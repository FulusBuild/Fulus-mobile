import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/sync_cursor_store.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/core/notifications/notification_service.dart';
import 'package:fulus_mobile/core/diagnostics/diagnostic_logger.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_enums.dart';

class _MockNotificationService extends Mock implements NotificationService {}
class _MockDiagnosticLogger extends Mock implements DiagnosticLogger {}

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
      cursorStore: SharedPreferencesSyncCursorStore(await SharedPreferences.getInstance()),
    );

    await notifier.recordPushSuccess(
      'business-1',
      hadOutboundWork: true,
    );

    expect(notifier.healthFor('business-1').lastPushAt, isNotNull);
  });
  test('health diagnostic identifies queued work without exporting local IDs', () async {
    final preferences = await SharedPreferences.getInstance();
    final logger = _MockDiagnosticLogger();
    when(() => logger.captureInfo(
          category: DiagnosticCategory.synchronization,
          title: 'Sync health',
          message: 'Periodic sync health snapshot.',
          technicalContext: any(named: 'technicalContext'),
        )).thenAnswer((_) async {});

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'operation-private-id',
        entityType: 'product_photo',
        entityLocalId: 'product-private-id',
        operation: 'upload',
        priority: 2,
        enqueuedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        syncAttempts: const Value(5),
        lastError: const Value('HTTP 403 permission denied'),
      ),
    );

    final notifier = SyncStatusNotifier(
      db: db,
      syncConfig: config,
      notificationService: notifications,
      preferences: preferences,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      diagnosticLogger: logger,
    );

    await notifier.emitHealthDiagnostic('business-1');

    final context = verify(() => logger.captureInfo(
          category: DiagnosticCategory.synchronization,
          title: 'Sync health',
          message: 'Periodic sync health snapshot.',
          technicalContext: captureAny(named: 'technicalContext'),
        )).captured.single as Map<String, String>;

    expect(context['pending_count'], '1');
    expect(context['attention_count'], '1');
    expect(context['pending_items_json'], contains('product_photo'));
    expect(context['pending_items_json'], contains('HTTP 403 permission denied'));
    expect(context['pending_items_json'], isNot(contains('product-private-id')));
    expect(context['pending_items_json'], isNot(contains('operation-private-id')));
    expect(context['unresolved_conflict_count'], '0');
  });

}
