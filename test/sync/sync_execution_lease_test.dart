import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
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

  test('canonical apply transaction fences lease takeover after expiry', () async {
    final directory = await Directory.systemTemp.createTemp('fulus-lease-fence-');
    final path = '${directory.path}/fulus.db';
    QueryExecutor openExecutor() => NativeDatabase(
      File(path),
      setup: (database) {
        database.execute('PRAGMA journal_mode=WAL');
        database.execute('PRAGMA busy_timeout=1000');
      },
    );
    final db1 = AppDatabase.forTesting(openExecutor());
    final db2 = AppDatabase.forTesting(openExecutor());

    final firstLease = SyncExecutionLease(
      db1,
      leaseDuration: const Duration(minutes: 2),
      acquisitionTimeout: const Duration(seconds: 2),
    );
    final secondLease = SyncExecutionLease(
      db2,
      acquisitionTimeout: const Duration(seconds: 2),
    );
    addTearDown(() async {
      await firstLease.release();
      await secondLease.release();
      await db1.close();
      await db2.close();
      await directory.delete(recursive: true);
    });

    expect(await firstLease.acquire(), isTrue);

    // Shorten the committed lease from a separate connection before the
    // transaction starts. The long lease duration keeps the renewal timer
    // inactive while the test deliberately lets the lease expire.
    await (db2.update(db2.syncRuntimeLeases)
          ..where((row) => row.name.equals(SyncExecutionLease.leaseName)))
        .write(
      SyncRuntimeLeasesCompanion(
        expiresAt: Value(DateTime.now().add(const Duration(seconds: 5))),
      ),
    );

    final transactionStarted = Completer<void>();
    final releaseTransaction = Completer<void>();
    final transaction = db1.transaction(() async {
      await firstLease.ensureHeldForTransaction();
      transactionStarted.complete();
      await releaseTransaction.future;
    });

    await transactionStarted.future;
    await Future<void>.delayed(const Duration(seconds: 6));

    // The takeover transaction reaches SQLite while db1 still owns the
    // writer lock. Native SQLite reports SQLITE_BUSY for that BEGIN IMMEDIATE
    // rather than completing the takeover while the canonical transaction is
    // open.
    final takeover = secondLease.acquire();
    await expectLater(takeover, throwsA(isA<Exception>()));

    releaseTransaction.complete();
    await transaction;
    expect(await secondLease.acquire(), isTrue);
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

  test('a resumed runtime stops before pull after another runtime takes over', () async {
    final firstEngine = _MockSyncEngine();
    final secondEngine = _MockSyncEngine();
    final firstStatus = _MockSyncStatusNotifier();
    final secondStatus = _MockSyncStatusNotifier();
    when(() => firstStatus.checkForStuckSyncAndNotify()).thenAnswer((_) async {});
    when(() => secondStatus.checkForStuckSyncAndNotify()).thenAnswer((_) async {});

    final releaseFirstEngine = Completer<void>();
    var firstPullCalls = 0;
    when(() => firstEngine.runOnce(manual: any(named: 'manual')))
        .thenAnswer((_) => releaseFirstEngine.future);
    when(() => secondEngine.runOnce(manual: any(named: 'manual')))
        .thenAnswer((_) async {});

    final config1 = await SyncConfig.load();
    final config2 = await SyncConfig.load();
    await config1.setEnabled(true);
    await config2.setEnabled(true);

    final firstTriggers = SyncTriggers(
      syncEngine: firstEngine,
      syncConfig: config1,
      syncStatusNotifier: firstStatus,
      executionLease: SyncExecutionLease(
        db,
        leaseDuration: const Duration(milliseconds: 50),
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
      pullFromServer: () async {
        firstPullCalls++;
      },
    );
    final secondTriggers = SyncTriggers(
      syncEngine: secondEngine,
      syncConfig: config2,
      syncStatusNotifier: secondStatus,
      executionLease: SyncExecutionLease(
        db,
        leaseDuration: const Duration(seconds: 1),
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
      pullFromServer: () async {},
    );

    final firstRun = firstTriggers.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await secondTriggers.syncNow();
    verify(() => secondEngine.runOnce(manual: any(named: 'manual'))).called(1);

    releaseFirstEngine.complete();
    await firstRun;

    verify(() => firstEngine.runOnce(manual: true)).called(1);
    expect(firstPullCalls, 0);

    firstTriggers.dispose();
    secondTriggers.dispose();
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
