import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

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

class _CountingHandler implements SyncHandler {
  final List<String> attemptedIds = [];

  @override
  Future<void> sync(SyncQueueItem item) async {
    attemptedIds.add(item.id);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('only one SyncEngine runtime can hold the SQLite execution lease', () async {
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

  test('a second runtime cannot drain the outbox while the first is active', () async {
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

    final started = Completer<void>();
    final release = Completer<void>();
    final firstHandler = _BlockingHandler(started, release);
    final secondHandler = _CountingHandler();

    final firstEngine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': firstHandler},
      executionLease: SyncExecutionLease(
        db,
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
    );
    final secondEngine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': secondHandler},
      executionLease: SyncExecutionLease(
        db,
        acquisitionTimeout: const Duration(milliseconds: 100),
      ),
    );

    final firstRun = firstEngine.runOnce();
    await started.future;

    await secondEngine.runOnce();
    expect(secondHandler.attemptedIds, isEmpty);

    release.complete();
    await firstRun;

    expect(firstHandler.attemptedIds, ['q1']);
    expect(await (db.select(db.syncQueueItems)).get(), isEmpty);
  });

  test('an abandoned lease expires and can be recovered by another runtime', () async {
    final firstLease = SyncExecutionLease(
      db,
      leaseDuration: const Duration(milliseconds: 50),
      acquisitionTimeout: const Duration(milliseconds: 200),
    );
    final secondLease = SyncExecutionLease(
      db,
      leaseDuration: const Duration(milliseconds: 50),
      acquisitionTimeout: const Duration(milliseconds: 500),
    );

    expect(await firstLease.acquire(), isTrue);
    expect(await secondLease.acquire(), isTrue);

    await secondLease.release();
    // Simulate the first runtime disappearing without calling release().
    // Its short test lease has already expired by the time the second runtime
    // acquires ownership.
  });
}
