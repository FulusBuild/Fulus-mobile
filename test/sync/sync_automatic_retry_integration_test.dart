import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/retry_policy.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockConnectivity extends Mock implements Connectivity {}
class _MockSyncStatusNotifier extends Mock implements SyncStatusNotifier {}

class _TransientHandler implements SyncHandler {
  int attempts = 0;
  final Completer<void> recovered = Completer<void>();

  @override
  Future<void> sync(SyncQueueItem item) async {
    attempts++;
    if (attempts == 1) {
      throw Exception('temporary cloud failure');
    }
    if (!recovered.isCompleted) {
      recovered.complete();
    }
  }
}

void main() {
  late AppDatabase db;
  late _MockConnectivity connectivity;
  late _MockSyncStatusNotifier statusNotifier;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connectivity = _MockConnectivity();
    statusNotifier = _MockSyncStatusNotifier();

    when(() => statusNotifier.checkForStuckSyncAndNotify())
        .thenAnswer((_) async {});
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'automatic periodic retry drains a transient failure while app remains open',
      () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
    final config = await SyncConfig.load();

    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: 'retry-item',
            entityType: 'widget',
            entityLocalId: 'retry-me',
            operation: 'create',
            priority: 0,
            enqueuedAt: DateTime.now(),
          ),
        );

    final handler = _TransientHandler();
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      retryPolicy: const RetryPolicy(baseDelay: Duration.zero),
    );

    Object? reportedError;
    final triggers = SyncTriggers(
      syncEngine: engine,
      syncConfig: config,
      syncStatusNotifier: statusNotifier,
      connectivity: connectivity,
      retryInterval: const Duration(milliseconds: 10),
      onSyncFailure: (error, _) => reportedError = error,
    );

    await triggers.start();
    await handler.recovered.future.timeout(const Duration(seconds: 1));
    // The handler can finish before SyncEngine commits the queue removal.
    // Wait for the trigger's active cycle to fully unwind before asserting
    // durable queue state.
    await triggers.waitForIdle();

    expect(handler.attempts, 2);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
    expect(reportedError, isNull);

    triggers.dispose();
  });
}
