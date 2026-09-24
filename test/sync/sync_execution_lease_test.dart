import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';

class _MockSyncEngine extends Mock implements SyncEngine {}
class _MockSyncStatusNotifier extends Mock implements SyncStatusNotifier {}

class _BlockingHandler implements SyncHandler {
  _BlockingHandler(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;
  final List<String> attemptedIds = [];

  @override
  Future<void> sync(SyncQueueItem item) async {
    attemptedIds.add(item.id);
    if (!started.isCompleted) started.complete();
    await release.future;
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('only one runtime can hold the SQLite execution lease', () async {
    final firstLease = SyncExecutionLease(
      db,
      acquisitionTimeout: const Duration(milliseconds: 100),
    );
    final secondLease = SyncExecutionLease(
      db,
      acquisitionTimeout: const Duration(milliseconds: 100),
    );

    expect(await firstLease.acquire(), isTrue);
    expect(await secondLease.acquire(), isFalse);

    await firstLease.release();

    expect(await secondLease.acquire(), isTrue);
    await secondLease.release();
  });

  test('an abandoned lease expires and can be recovered by another runtime', () async {
    final firstLease = SyncExecutionLease(
      db,
      leaseDuration: const Duration(milliseconds: 50),
      acquisitionTimeout: const Duration(milliseconds: 100),
    );
    final secondLease = SyncExecutionLease(
      db,
      leaseDuration: const Duration(milliseconds: 50),
      acquisitionTimeout: const Duration(milliseconds: 500),
    );

    expect(await firstLease.acquire(), isTrue);
    expect(await secondLease.acquire(), isTrue);

    await secondLease.release();
    // The first runtime deliberately never releases its lease, simulating a
    // process death. The second runtime could take ownership only after expiry.
  });

  test('the lease covers the full push-pull cycle, not only queue draining',
      () async {
    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: 'q1',
            entityType: 'widget',
            entityLocalId: 'widget-1',
            operation: 'update',
            priority: 0,
            enqueuedAt: DateTime.now(),
          ),
        );

    final firstEngine = _MockSyncEngine();
    final secondEngine = _MockSyncEngine();
    final firstStatus = _MockSyncStatusNotifier();
    final secondStatus = _MockSyncStatusNotifier();
    when(() => firstStatus.checkForStuckSyncAndNotify()).thenAnswer((_) async {});
    when(() => secondStatus.checkForStuckSyncAndNotify()).thenAnswer((_) async {});

    final firstPullStarted = Completer<void>();
    final releaseFirstPull = Completer<void>();

    when(() => firstEngine.runOnce(manual: any(named: 'manual')))
        .thenAnswer((_) async {});
    when(() => secondEngine.runOnce(manual: any(named: 'manual')))
        .thenAnswer((_) async {});

    final config1 = await SyncConfig.load();
    final config2 = await SyncConfig.load();

    final firstTriggers = SyncTriggers(
      syncEngine: firstEngine,
      syncConfig: config1,
      syncStatusNotifier: firstStatus,
      executionLease: SyncExecutionLease(
        db,
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
      pullFromServer: () async {
        firstPullStarted.complete();
        await releaseFirstPull.future;
      },
    );
    final secondTriggers = SyncTriggers(
      syncEngine: secondEngine,
      syncConfig: config2,
      syncStatusNotifier: secondStatus,
      executionLease: SyncExecutionLease(
        db,
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
      pullFromServer: () async {},
    );

    final firstRun = firstTriggers.syncNow();
    await firstPullStarted.future;

    await secondTriggers.syncNow();
    verifyNever(() => secondEngine.runOnce(manual: any(named: 'manual')));

    releaseFirstPull.complete();
    await firstRun;

    firstTriggers.dispose();
    secondTriggers.dispose();
  });

  test('a SyncEngine without an execution lease remains usable in isolation',
      () async {
    final handler = _BlockingHandler(Completer<void>(), Completer<void>());
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
    );

    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: 'q-isolated',
            entityType: 'widget',
            entityLocalId: 'widget-isolated',
            operation: 'update',
            priority: 0,
            enqueuedAt: DateTime.now(),
          ),
        );

    final release = Completer<void>();
    final started = Completer<void>();
    final isolated = _BlockingHandler(started, release);
    final isolatedEngine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': isolated},
    );

    final run = isolatedEngine.runOnce();
    await started.future;
    release.complete();
    await run;
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });
}
