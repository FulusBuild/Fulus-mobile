import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';

class _MockSyncEngine extends Mock implements SyncEngine {}
class _MockSyncStatusNotifier extends Mock implements SyncStatusNotifier {}

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

  test('a stale lease is recoverable by another runtime', () async {
    final now = DateTime.now();
    await db.into(db.syncRuntimeLeases).insert(
          SyncRuntimeLeasesCompanion.insert(
            name: SyncExecutionLease.leaseName,
            ownerId: 'dead-runtime',
            acquiredAt: now.subtract(const Duration(minutes: 5)),
            expiresAt: now.subtract(const Duration(minutes: 1)),
          ),
        );

    final secondLease = SyncExecutionLease(
      db,
      acquisitionTimeout: const Duration(milliseconds: 100),
    );

    expect(await secondLease.acquire(), isTrue);
    await secondLease.release();
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
    await config1.setEnabled(true);

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
    await config2.setEnabled(true);

    final firstRun = firstTriggers.syncNow();
    await firstPullStarted.future;

    await secondTriggers.syncNow();
    verifyNever(() => secondEngine.runOnce(manual: any(named: 'manual')));

    releaseFirstPull.complete();
    await firstRun;

    firstTriggers.dispose();
    secondTriggers.dispose();
  });

}
