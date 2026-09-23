import 'dart:async';

import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every entityLocalId it was asked to sync, and does whatever
/// [onSync] scripts for that call — letting each test control success
/// vs. a specific thrown failure per item, per call, directly.
class _ScriptedHandler implements SyncHandler {
  _ScriptedHandler(this.onSync);

  final Future<void> Function(SyncQueueItem item) onSync;
  final List<String> attemptedIds = [];

  @override
  Future<void> sync(SyncQueueItem item) async {
    attemptedIds.add(item.entityLocalId);
    await onSync(item);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedItem({
    required String id,
    String entityType = 'widget',
    required String entityLocalId,
    String operation = 'create',
    int priority = 0,
    required DateTime enqueuedAt,
    int syncAttempts = 0,
    DateTime? lastAttemptedAt,
  }) async {
    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: id,
            entityType: entityType,
            entityLocalId: entityLocalId,
            operation: operation,
            priority: priority,
            enqueuedAt: enqueuedAt,
            syncAttempts: Value(syncAttempts),
            lastAttemptedAt: Value(lastAttemptedAt),
          ),
        );
  }

  Future<List<SyncQueueItem>> allQueueItems() => db.select(db.syncQueueItems).get();

  test('processes items in priority order, then oldest-first within a priority',
      () async {
    final base = DateTime(2026, 1, 1);
    await seedItem(
      id: 'q1',
      entityLocalId: 'low-priority-newer',
      priority: 1,
      enqueuedAt: base.add(const Duration(minutes: 5)),
    );
    await seedItem(
      id: 'q2',
      entityLocalId: 'high-priority-newer',
      priority: 0,
      enqueuedAt: base.add(const Duration(minutes: 10)),
    );
    await seedItem(
      id: 'q3',
      entityLocalId: 'high-priority-older',
      priority: 0,
      enqueuedAt: base,
    );

    final handler = _ScriptedHandler((_) async {});
    final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

    await engine.runOnce();

    expect(handler.attemptedIds, [
      'high-priority-older',
      'high-priority-newer',
      'low-priority-newer',
    ]);
  });

  test('does not drain the queue when the sync readiness guard is false', () async {
    await seedItem(id: 'q1', entityLocalId: 'blocked-by-readiness', enqueuedAt: DateTime.now());
    final handler = _ScriptedHandler((_) async {});
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      canSync: () async => false,
    );

    await engine.runOnce();

    expect(handler.attemptedIds, isEmpty);
    expect(await allQueueItems(), hasLength(1));
  });

  test('removes an item from the queue on success', () async {
    await seedItem(id: 'q1', entityLocalId: 'a', enqueuedAt: DateTime.now());
    final handler = _ScriptedHandler((_) async {});
    final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

    await engine.runOnce();

    expect(await allQueueItems(), isEmpty);
  });

  test(
      'a BusinessRuleFailure marks the item attentionNeeded immediately '
      'and the run continues to the next item', () async {
    final now = DateTime.now();
    await seedItem(id: 'q1', entityLocalId: 'rejected', enqueuedAt: now);
    await seedItem(
      id: 'q2',
      entityLocalId: 'fine',
      enqueuedAt: now.add(const Duration(seconds: 1)),
    );

    final handler = _ScriptedHandler((item) async {
      if (item.entityLocalId == 'rejected') {
        throw const BusinessRuleFailure('Insufficient stock.');
      }
    });
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      maxAttemptsBeforeAttentionNeeded: 5,
    );

    await engine.runOnce();

    expect(handler.attemptedIds, ['rejected', 'fine']);

    final remaining = await allQueueItems();
    expect(remaining, hasLength(1));
    expect(remaining.single.entityLocalId, 'rejected');
    expect(remaining.single.syncAttempts, 5);
    expect(remaining.single.lastError, '[BLOCKED] Insufficient stock.');
  });

  test(
      'an authentication failure stays retryable and stops the current drain',
      () async {
    final now = DateTime.now();
    await seedItem(id: 'q1', entityLocalId: 'needs-auth', enqueuedAt: now);
    await seedItem(
      id: 'q2',
      entityLocalId: 'must-wait-for-auth',
      enqueuedAt: now.add(const Duration(seconds: 1)),
    );

    final handler = _ScriptedHandler((item) async {
      if (item.entityLocalId == 'needs-auth') {
        throw const AuthFailure.sessionExpired();
      }
    });
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      maxAttemptsBeforeAttentionNeeded: 5,
    );

    await engine.runOnce();

    expect(handler.attemptedIds, ['needs-auth']);

    final remaining = await allQueueItems();
    expect(remaining, hasLength(2));
    final authRow = remaining.firstWhere((r) => r.entityLocalId == 'needs-auth');
    expect(authRow.syncAttempts, 0);
    expect(authRow.lastError, 'Please sign in again to continue.');
    expect(authRow.lastAttemptedAt, isNull);

    // Once the session is restored, the item is immediately eligible again
    // rather than being trapped behind the normal transient-failure backoff.
    final successHandler = _ScriptedHandler((_) async {});
    final recoveredEngine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': successHandler},
    );
    await recoveredEngine.runOnce();

    expect(successHandler.attemptedIds, ['needs-auth', 'must-wait-for-auth']);
    expect(await allQueueItems(), isEmpty);
  });

  test(
      'a transient failure increments attempts by one and the run continues '
      'to later independent items', () async {
    final now = DateTime.now();
    await seedItem(id: 'q1', entityLocalId: 'flaky', enqueuedAt: now);
    await seedItem(
      id: 'q2',
      entityLocalId: 'never-reached',
      enqueuedAt: now.add(const Duration(seconds: 1)),
    );

    final handler = _ScriptedHandler((item) async {
      if (item.entityLocalId == 'flaky') {        throw Exception('Connection reset');
      }
    });
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      maxAttemptsBeforeAttentionNeeded: 5,
    );

    await engine.runOnce();

    expect(handler.attemptedIds, ['flaky', 'never-reached']);

    final remaining = await allQueueItems();
    expect(remaining, hasLength(1));
    final flakyRow = remaining.firstWhere((r) => r.entityLocalId == 'flaky');
    expect(flakyRow.syncAttempts, 1);
  });

  test(
      'retryable work continues automatically after the attention threshold',
      () async {
    final now = DateTime.now();
    await seedItem(
      id: 'q1',
      entityLocalId: 'transient-after-threshold',
      enqueuedAt: now,
      syncAttempts: 2,
      lastAttemptedAt: now.subtract(const Duration(hours: 1)),
    );

    final handler = _ScriptedHandler((_) async => throw Exception('server down'));
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      maxAttemptsBeforeAttentionNeeded: 2,
    );

    await engine.runOnce();

    expect(handler.attemptedIds, ['transient-after-threshold']);
    final row = (await allQueueItems()).single;
    expect(row.syncAttempts, 2);
    expect(row.lastError, 'Exception: server down');
  });

  test(
      'permanently blocked work is not retried automatically but manual retry remains possible',
      () async {
    final now = DateTime.now();
    await seedItem(
      id: 'q1',
      entityLocalId: 'blocked',
      enqueuedAt: now,
      syncAttempts: 2,
      lastAttemptedAt: now.subtract(const Duration(hours: 1)),
    );
    await (db.update(db.syncQueueItems)..where((q) => q.id.equals('q1'))).write(
      const SyncQueueItemsCompanion(lastError: Value('[BLOCKED] permanent')),
    );

    final handler = _ScriptedHandler((_) async {});
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {'widget': handler},
      maxAttemptsBeforeAttentionNeeded: 2,
    );

    await engine.runOnce();
    expect(handler.attemptedIds, isEmpty);

    await engine.runOnce(manual: true);
    expect(handler.attemptedIds, ['blocked']);
  });

  test(
      'an entityType with no registered handler is marked attentionNeeded '
      'immediately and the run continues', () async {
    final now = DateTime.now();
    await seedItem(
      id: 'q1',
      entityType: 'unregistered-type',
      entityLocalId: 'orphan',
      enqueuedAt: now,
    );
    await seedItem(
      id: 'q2',
      entityLocalId: 'fine',
      enqueuedAt: now.add(const Duration(seconds: 1)),
    );

    final handler = _ScriptedHandler((_) async {});
    final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

    await engine.runOnce();

    expect(handler.attemptedIds, ['fine']);

    final remaining = await allQueueItems();
    expect(remaining, hasLength(1));
    expect(remaining.single.entityLocalId, 'orphan');
    expect(remaining.single.lastError, contains('No sync handler registered'));
  });

  test('concurrent triggers share one in-flight drain', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    await seedItem(id: 'q1', entityLocalId: 'slow', enqueuedAt: DateTime.now());

    final handler = _ScriptedHandler((_) async {
      started.complete();
      await release.future;
    });
    final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

    final first = engine.runOnce();
    await started.future;
    final second = engine.runOnce();
    expect(identical(first, second), isTrue);

    release.complete();
    await Future.wait([first, second]);
    expect(handler.attemptedIds, ['slow']);
    expect(await allQueueItems(), isEmpty);
  });

  test(
      'retries dependency-blocked work after its prerequisite succeeds in the same drain',
      () async {
    final now = DateTime.now();
    await seedItem(
      id: 'dependent',
      entityLocalId: 'product',
      enqueuedAt: now,
      priority: 0,
    );
    await seedItem(
      id: 'prerequisite',
      entityLocalId: 'category',
      enqueuedAt: now.add(const Duration(seconds: 1)),
      priority: 0,
    );

    var productAttempts = 0;
    final handler = _ScriptedHandler((item) async {
      if (item.entityLocalId == 'product' && productAttempts++ == 0) {
        throw const SyncFailure(
          kind: SyncErrorKind.dependencyNotReady,
          message: 'Category has no server identity yet.',
        );
      }
    });
    final engine = SyncEngine(
      db: db,
      handlersByEntityType: {
        'widget': handler,
      },
    );

    // Both queue rows use the same handler so the test isolates engine
    // scheduling rather than a particular domain handler.
    await engine.runOnce();

    expect(handler.attemptedIds, ['product', 'category', 'product']);
    expect(await allQueueItems(), isEmpty);
  });

  group('retry backoff', () {
    test('an item that failed moments ago is skipped on an automatic run', () async {
      final now = DateTime.now();
      await seedItem(
        id: 'q1',
        entityLocalId: 'still-backing-off',
        enqueuedAt: now,
        syncAttempts: 1,
        lastAttemptedAt: now.subtract(const Duration(seconds: 5)),
      );

      final handler = _ScriptedHandler((_) async {});
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce();

      expect(handler.attemptedIds, isEmpty);
    });

    test('the same item is attempted anyway on a manual run', () async {
      final now = DateTime.now();
      await seedItem(
        id: 'q1',
        entityLocalId: 'still-backing-off',
        enqueuedAt: now,
        syncAttempts: 1,
        lastAttemptedAt: now.subtract(const Duration(seconds: 5)),
      );

      final handler = _ScriptedHandler((_) async {});
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce(manual: true);

      expect(handler.attemptedIds, ['still-backing-off']);
    });

    test('an item whose backoff window has fully elapsed is retried automatically', () async {
      final now = DateTime.now();
      await seedItem(
        id: 'q1',
        entityLocalId: 'ready-again',
        enqueuedAt: now,
        syncAttempts: 1,
        lastAttemptedAt: now.subtract(const Duration(hours: 1)),
      );

      final handler = _ScriptedHandler((_) async {});
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce();

      expect(handler.attemptedIds, ['ready-again']);
    });

    test('an item that has never been attempted is never held back by backoff', () async {
      await seedItem(
        id: 'q1',
        entityLocalId: 'brand-new',
        enqueuedAt: DateTime.now(),
      );

      final handler = _ScriptedHandler((_) async {});
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce();

      expect(handler.attemptedIds, ['brand-new']);
    });
  });

  group('conflict detection', () {
    test('a BusinessRuleFailure that reads like a conflict is annotated', () async {
      await seedItem(id: 'q1', entityLocalId: 'a', enqueuedAt: DateTime.now());
      final handler = _ScriptedHandler((_) async {
        throw const BusinessRuleFailure("SKU 'RICE-5KG' already exists.");
      });
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce();

      final remaining = await allQueueItems();
      expect(remaining.single.lastError, startsWith('[CONFLICT]'));
      expect(remaining.single.lastError, contains('already exists'));
    });

    test('machine-readable sync conflicts are persisted as durable records', () async {
      await seedItem(id: 'q-conflict', entityLocalId: 'customer-1', entityType: 'customer', enqueuedAt: DateTime.now());
      final handler = _ScriptedHandler((_) async {
        throw const BusinessRuleFailure(
          'SYNC_CONFLICT: Customer changed on another device.',
          code: 'SYNC_CONFLICT',
        );
      });
      final engine = SyncEngine(db: db, handlersByEntityType: {'customer': handler});

      await engine.runOnce();

      final conflicts = await db.select(db.syncConflictRecords).get();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.operationId, 'q-conflict');
      expect(conflicts.single.entityType, 'customer');
      expect(conflicts.single.code, 'SYNC_CONFLICT');
      expect(conflicts.single.resolvedAt, isNull);
    });

    test('successful newer mutation removes older conflicted outbox item', () async {
      final base = DateTime(2026, 1, 1);
      await seedItem(
        id: 'q-old',
        entityType: 'customer',
        entityLocalId: 'customer-1',
        enqueuedAt: base,
        syncAttempts: 5,
        lastAttemptedAt: base,
      );
      await db.into(db.syncConflictRecords).insert(
        SyncConflictRecordsCompanion.insert(
          id: 'q-old:conflict',
          operationId: 'q-old',
          entityType: 'customer',
          entityLocalId: 'customer-1',
          code: const Value('SYNC_CONFLICT'),
          message: 'Customer changed on another device.',
          createdAt: base.add(const Duration(seconds: 1)),
        ),
      );
      await seedItem(
        id: 'q-new',
        entityType: 'customer',
        entityLocalId: 'customer-1',
        enqueuedAt: base.add(const Duration(minutes: 1)),
      );

      final handler = _ScriptedHandler((item) async {
        expect(item.id, 'q-new');
      });
      final engine = SyncEngine(
        db: db,
        handlersByEntityType: {'customer': handler},
      );

      await engine.runOnce();

      expect(await allQueueItems(), isEmpty);
      final conflicts = await db.select(db.syncConflictRecords).get();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.resolvedAt, isNotNull);
      expect(
        conflicts.single.resolution,
        'superseded_by_successful_entity_update',
      );
    });

    test('an ordinary BusinessRuleFailure is left exactly as the handler reported it', () async {
      await seedItem(id: 'q1', entityLocalId: 'a', enqueuedAt: DateTime.now());
      final handler = _ScriptedHandler((_) async {
        throw const BusinessRuleFailure('Insufficient stock.');
      });
      final engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

      await engine.runOnce();

      final remaining = await allQueueItems();
      expect(remaining.single.lastError, '[BLOCKED] Insufficient stock.');
    });
  });
  test(
      'a queue item enqueued during an active drain triggers a follow-up drain',
      () async {
    final firstStarted = Completer<void>();
    final secondProcessed = Completer<void>();    late SyncEngine engine;

    await seedItem(
      id: 'q1',
      entityLocalId: 'first',
      enqueuedAt: DateTime.now(),
    );

    final handler = _ScriptedHandler((item) async {
      if (item.entityLocalId == 'first') {
        firstStarted.complete();
        await seedItem(
          id: 'q2',
          entityLocalId: 'enqueued-during-drain',
          enqueuedAt: DateTime.now().add(const Duration(seconds: 1)),
        );
        engine.runOnce();
      } else if (item.entityLocalId == 'enqueued-during-drain') {
        secondProcessed.complete();
      }
    });

    engine = SyncEngine(db: db, handlersByEntityType: {'widget': handler});

    final firstRun = engine.runOnce();
    await firstStarted.future;
    await firstRun;
    await secondProcessed.future;

    expect(handler.attemptedIds, ['first', 'enqueued-during-drain']);
    expect(await allQueueItems(), isEmpty);
  });
}