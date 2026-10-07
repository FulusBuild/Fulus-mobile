import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_coordinator.dart';
import 'package:fulus_mobile/data/local/sync_cursor_store.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

class MockFulusSyncApi extends Mock implements FulusSyncApi {}

void main() {
  test('persists cursor only after every change is applied', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [
        FulusSyncChange(sequence: 1, entityType: 'customer', entityId: 'c1', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
        FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
      ], cursor: 0, nextCursor: 2, hasMore: false,
    ));
    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (change) async => applied.add(change.sequence));
    final cursor = await coordinator.pullAndApply(businessId: 'b1');
    expect(cursor, 2);
    expect(applied, [1, 2]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 2);
  });

  test('cursor persistence failure leaves the durable cursor unchanged after local apply', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(
        sequence: 1,
        entityType: 'customer',
        entityId: 'c1',
        operation: 'upsert',
        payload: const {},
        createdAt: DateTime.utc(2026, 1, 1),
      )],
      cursor: 0,
      nextCursor: 1,
      hasMore: false,
    ));
    var persistAttempts = 0;
    var applyCount = 0;
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async => applyCount++,
      persistCursor: (_, __) async {
        persistAttempts++;
        return false;
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<StateError>()),
    );

    expect(applyCount, 1);
    expect(persistAttempts, 1);
    expect(coordinator.cursorFor('b1'), 0);
    expect(preferences.getInt('fulus_sync_cursor_b1'), isNull);
  });

  test('setCursor reports boundary persistence failure instead of claiming recovery is acknowledged', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final coordinator = FulusSyncCoordinator(
      api: MockFulusSyncApi(),
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
      persistCursor: (_, __) async => false,
    );

    await expectLater(
      coordinator.setCursor('b1', 42),
      throwsA(isA<StateError>()),
    );
    expect(coordinator.cursorFor('b1'), 0);
    expect(preferences.getInt('fulus_sync_cursor_b1'), isNull);
  });

  test('does not advance cursor past a failed change', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 1});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 1, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 1, nextCursor: 2, hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (_) async => throw StateError('apply failed'));
    await expectLater(coordinator.pullAndApply(businessId: 'b1'), throwsA(isA<StateError>()));
    expect(preferences.getInt('fulus_sync_cursor_b1'), 1);
  });

  test('uses the applied sequence for paging and never persists nextCursor early', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 1, entityType: 'customer', entityId: 'c1', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 0, nextCursor: 99, hasMore: true,
    ));
    when(() => api.pullChanges(businessId: 'b1', cursor: 1, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 1, nextCursor: 2, hasMore: false,
    ));

    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (change) async => applied.add(change.sequence),
    );

    final cursor = await coordinator.pullAndApply(businessId: 'b1');

    expect(cursor, 2);
    expect(applied, [1, 2]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 2);
    verify(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).called(1);
    verify(() => api.pullChanges(businessId: 'b1', cursor: 1, limit: 100)).called(1);
  });

  test('skips replayed changes at or before the durable cursor', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 5});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 5, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [
        FulusSyncChange(sequence: 4, entityType: 'customer', entityId: 'old', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
        FulusSyncChange(sequence: 5, entityType: 'customer', entityId: 'replayed', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
        FulusSyncChange(sequence: 6, entityType: 'customer', entityId: 'new', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
      ],
      cursor: 5,
      nextCursor: 6,
      hasMore: false,
    ));
    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (change) async => applied.add(change.sequence),
    );

    final cursor = await coordinator.pullAndApply(businessId: 'b1');

    expect(cursor, 6);
    expect(applied, [6]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 6);
  });

  test('acknowledges a remote change without applying it when a local mutation is pending', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 7, entityType: 'customer', entityId: 'c1', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 0, nextCursor: 7, hasMore: false,
    ));
    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (change) async => applied.add(change.sequence),
      shouldApplyChange: (_) async => false,
    );

    final cursor = await coordinator.pullAndApply(businessId: 'b1');

    expect(applied, isEmpty);
    expect(cursor, 7);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 7);
  });

  test('serializes a concurrent local mutation behind canonical reconciliation', () async {
    final directory = await Directory.systemTemp.createTemp('fulus-sync-race-');
    final path = directory.path + '/fulus.db';
    QueryExecutor openExecutor() => NativeDatabase(
      File(path),
      setup: (database) {
        database.execute('PRAGMA journal_mode=WAL');
        database.execute('PRAGMA busy_timeout=5000');
      },
    );
    final db1 = AppDatabase.forTesting(openExecutor());
    final db2 = AppDatabase.forTesting(openExecutor());
    addTearDown(() async {
      await db1.close();
      await db2.close();
      await directory.delete(recursive: true);
    });
    final now = DateTime.utc(2026, 1, 1);
    await db1.into(db1.customers).insert(CustomersCompanion.insert(
      localId: 'customer-local', serverId: const Value('customer-server'),
      name: 'Before', createdAt: now, updatedAt: now, syncStatus: SyncStatus.settled,
    ));
    final queue = SyncQueue(db2);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer(
      (_) async => FulusSyncPullResponse(
        changes: [FulusSyncChange(sequence: 1, entityType: 'customer', entityId: 'customer-server', operation: 'upsert', payload: const {}, createdAt: now)],
        cursor: 0, nextCursor: 1, hasMore: false,
      ),
    );
    final eligibilityChecked = Completer<void>();
    final canonicalApplied = Completer<void>();
    final coordinator = FulusSyncCoordinator(
      api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {
        await (db1.update(db1.customers)..where((c) => c.serverId.equals('customer-server')))
            .write(const CustomersCompanion(name: Value('Canonical overwrite')));
        canonicalApplied.complete();
      },
      shouldApplyChange: (_) async {
        eligibilityChecked.complete();
        return true;
      },
      withApplyTransaction: (action) => db1.transaction(action),
    );

    final pull = coordinator.pullAndApply(businessId: 'b1');
    await eligibilityChecked.future;
    final localMutation = db2.transaction(() async {
      await (db2.update(db2.customers)..where((c) => c.serverId.equals('customer-server')))
          .write(const CustomersCompanion(name: Value('Local edit'), syncStatus: Value(SyncStatus.pending)));
      await queue.enqueue(SyncTask.updateCustomer('customer-local'));
    });

    await pull;
    await canonicalApplied.future;
    await localMutation;

    final localRow = await (db2.select(db2.customers)..where((c) => c.serverId.equals('customer-server'))).getSingle();
    expect(localRow.name, 'Local edit');
    expect(localRow.syncStatus, SyncStatus.pending);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 1);
  });

  test('a stale page is discarded when another runtime advances the durable cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    final pageReady = Completer<void>();
    final releasePage = Completer<void>();

    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async {
      pageReady.complete();
      await releasePage.future;
      return FulusSyncPullResponse(
        changes: [FulusSyncChange(
          sequence: 1,
          entityType: 'customer',
          entityId: 'c1',
          operation: 'upsert',
          payload: const {},
          createdAt: DateTime.utc(2026, 1, 1),
        )],
        cursor: 0,
        nextCursor: 1,
        hasMore: false,
      );
    });

    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (change) async => applied.add(change.sequence),
    );

    final pull = coordinator.pullAndApply(businessId: 'b1');
    await pageReady.future;

    await preferences.setInt('fulus_sync_cursor_b1', 1);
    releasePage.complete();
    final cursor = await pull;

    expect(applied, isEmpty);
    expect(cursor, 1);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 1);
  });

  test('keeps cursors isolated per business', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 7});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b2', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 3, entityType: 'customer', entityId: 'c3', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 0,
      nextCursor: 3,
      hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
    );

    await coordinator.pullAndApply(businessId: 'b2');

    expect(coordinator.cursorFor('b1'), 7);
    expect(coordinator.cursorFor('b2'), 3);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 7);
    expect(preferences.getInt('fulus_sync_cursor_b2'), 3);
  });

  test('setCursor persists an authoritative restore snapshot boundary', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 4});
    final preferences = await SharedPreferences.getInstance();
    final coordinator = FulusSyncCoordinator(
      api: MockFulusSyncApi(),
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
    );

    await coordinator.setCursor('b1', 27);

    expect(coordinator.cursorFor('b1'), 27);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 27);
  });

  test('setCursor rejects a negative restore boundary', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final coordinator = FulusSyncCoordinator(
      api: MockFulusSyncApi(),
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
    );

    expect(() => coordinator.setCursor('b1', -1), throwsArgumentError);
  });

  test('resetCursor removes only the selected business cursor', () async {
    SharedPreferences.setMockInitialValues({
      'fulus_sync_cursor_b1': 7,
      'fulus_sync_cursor_b2': 3,
    });
    final preferences = await SharedPreferences.getInstance();
    final coordinator = FulusSyncCoordinator(
      api: MockFulusSyncApi(),
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
    );

    await coordinator.resetCursor('b1');

    expect(coordinator.cursorFor('b1'), 0);
    expect(coordinator.cursorFor('b2'), 3);
  });

  test('rejects reordered change-feed pages before acknowledgement', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 3, entityType: 'customer', entityId: 'c3', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)), FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 0, nextCursor: 3, hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (_) async {});
    await expectLater(coordinator.pullAndApply(businessId: 'b1'), throwsA(isA<StateError>()));
    expect(preferences.getInt('fulus_sync_cursor_b1') ?? 0, 0);
  });

  test('rejects duplicate sequence values before acknowledgement', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)), FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2b', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 0, nextCursor: 2, hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (_) async {});
    await expectLater(coordinator.pullAndApply(businessId: 'b1'), throwsA(isA<StateError>()));
    expect(preferences.getInt('fulus_sync_cursor_b1') ?? 0, 0);
  });

  test('rejects an empty page that claims more changes exist', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: const [], cursor: 0, nextCursor: 0, hasMore: true,
    ));
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (_) async {});
    await expectLater(coordinator.pullAndApply(businessId: 'b1'), throwsA(isA<StateError>()));
    expect(preferences.getInt('fulus_sync_cursor_b1') ?? 0, 0);
  });

  test('rejects a response cursor ahead of the requested durable cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 6, entityType: 'customer', entityId: 'c6', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 5, nextCursor: 6, hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(api: api, cursorStore: SharedPreferencesSyncCursorStore(preferences), applyChange: (_) async {});
    await expectLater(coordinator.pullAndApply(businessId: 'b1'), throwsA(isA<StateError>()));
    expect(preferences.getInt('fulus_sync_cursor_b1') ?? 0, 0);
  });

  test('prepares remote changes before opening the local apply transaction', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).thenAnswer(
      (_) async => FulusSyncPullResponse(
        changes: [
          FulusSyncChange(
            sequence: 1,
            entityType: 'customer',
            entityId: 'c1',
            operation: 'upsert',
            payload: const {},
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        cursor: 0,
        nextCursor: 1,
        hasMore: false,
      ),
    );

    final events = <String>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      applyChange: (_) async {},
      shouldApplyChange: (_) async {
        events.add('eligibility');
        return true;
      },
      prepareChanges: (changes) async {
        events.add('prepare:start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events.add('prepare:end');
        return changes;
      },
      applyPreparedChanges: (prepared, applicable) async {
        events.add('apply:' + (prepared as List<FulusSyncChange>).length.toString() + ':' + applicable.length.toString());
      },
      withApplyTransaction: (action) async {
        events.add('transaction:start');
        await action();
        events.add('transaction:end');
      },
    );

    await coordinator.pullAndApply(businessId: 'b1');

    expect(
      events,
      [
        'prepare:start',
        'prepare:end',
        'transaction:start',
        'eligibility',
        'apply:1:1',
        'transaction:end',
      ],
    );
    expect(preferences.getInt('fulus_sync_cursor_b1'), 1);
  });


  test('persists a poison canonical change without advancing the cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    final changes = [
      FulusSyncChange(
        sequence: 1,
        entityType: 'customer',
        entityId: 'c1',
        operation: 'upsert',
        payload: const {},
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      FulusSyncChange(
        sequence: 2,
        entityType: 'sale',
        entityId: 's2',
        operation: 'upsert',
        payload: const {},
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100))
        .thenAnswer((_) async => FulusSyncPullResponse(
              changes: changes,
              cursor: 0,
              nextCursor: 2,
              hasMore: false,
            ));

    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 3,
      blockedRetryBaseDelay: Duration.zero,
      now: () => DateTime.utc(2026, 1, 2),
      applyChange: (change) async {
        if (change.sequence == 2) {
          throw SyncCanonicalChangeApplyFailure(
            change,
            StateError('malformed canonical sale'),
          );
        }
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<SyncCanonicalChangeBlocked>()),
    );

    expect(coordinator.cursorFor('b1'), 0);
    final blocked = coordinator.blockedChangeFor('b1');
    expect(blocked, isNotNull);
    expect(blocked!.sequence, 2);
    expect(blocked.attemptCount, 1);
    expect(blocked.errorMessage, contains('malformed canonical sale'));
  });

  test('a durable poison barrier survives a new coordinator instance and stops after its retry budget', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100))
        .thenAnswer((_) async => FulusSyncPullResponse(
              changes: [
                FulusSyncChange(
                  sequence: 9,
                  entityType: 'sale',
                  entityId: 's9',
                  operation: 'upsert',
                  payload: const {},
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
              cursor: 0,
              nextCursor: 9,
              hasMore: false,
            ));

    final now = DateTime.utc(2026, 1, 2);
    final first = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 2,
      blockedRetryBaseDelay: Duration.zero,
      now: () => now,
      applyChange: (change) async {
        throw SyncCanonicalChangeApplyFailure(
          change,
          StateError('poison'),
        );
      },
    );

    await expectLater(
      first.pullAndApply(businessId: 'b1'),
      throwsA(isA<SyncCanonicalChangeBlocked>()),
    );
    expect(preferences.getString('fulus_sync_blocked_b1'), isNotNull);

    final second = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 2,
      blockedRetryBaseDelay: Duration.zero,
      now: () => now,
      applyChange: (change) async {
        throw SyncCanonicalChangeApplyFailure(
          change,
          StateError('poison'),
        );
      },
    );

    await expectLater(
      second.pullAndApply(businessId: 'b1'),
      throwsA(
        isA<SyncCanonicalChangeBlocked>()
            .having((e) => e.attemptCount, 'attempt count', 2),
      ),
    );

    final third = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 2,
      blockedRetryBaseDelay: Duration.zero,
      now: () => now,
      applyChange: (_) async {},
    );

    await expectLater(
      third.pullAndApply(businessId: 'b1'),
      throwsA(
        isA<SyncCanonicalChangeBlocked>()
            .having((e) => e.exhausted, 'exhausted', isTrue),
      ),
    );
    verify(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).called(2);
  });

  test('successful retry clears the poison barrier and then acknowledges the change', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100))
        .thenAnswer((_) async => FulusSyncPullResponse(
              changes: [
                FulusSyncChange(
                  sequence: 4,
                  entityType: 'customer',
                  entityId: 'c4',
                  operation: 'upsert',
                  payload: const {},
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
              cursor: 0,
              nextCursor: 4,
              hasMore: false,
            ));

    var fail = true;
    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 3,
      blockedRetryBaseDelay: Duration.zero,
      now: () => DateTime.utc(2026, 1, 2),
      applyChange: (change) async {
        if (fail) {
          throw SyncCanonicalChangeApplyFailure(change, StateError('temporary poison'));
        }
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<SyncCanonicalChangeBlocked>()),
    );
    expect(coordinator.cursorFor('b1'), 0);

    fail = false;
    final cursor = await coordinator.pullAndApply(businessId: 'b1');

    expect(cursor, 4);
    expect(coordinator.cursorFor('b1'), 4);
    expect(coordinator.blockedChangeFor('b1'), isNull);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 4);
  });

  test('authoritative recovery clears a blocked canonical change', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesSyncCursorStore(preferences);
    final change = FulusSyncChange(
      sequence: 12,
      entityType: 'sale',
      entityId: 's12',
      operation: 'upsert',
      payload: const {},
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await store.recordBlockedChange(
      businessId: 'b1',
      change: SyncBlockedChange(
        sequence: change.sequence,
        changeId: '12:sale:s12:upsert',
        entityType: change.entityType,
        entityId: change.entityId,
        operation: change.operation,
        firstSeenAt: DateTime.utc(2026, 1, 1),
        lastAttemptedAt: DateTime.utc(2026, 1, 1),
        attemptCount: 5,
        errorCode: null,
        errorMessage: 'poison',
      ),
    );

    final coordinator = FulusSyncCoordinator(
      api: MockFulusSyncApi(),
      cursorStore: store,
      applyChange: (_) async {},
    );

    await coordinator.setCursor('b1', 12);

    expect(coordinator.cursorFor('b1'), 12);
    expect(coordinator.blockedChangeFor('b1'), isNull);
  });

  test('explicit release permits a new retry without acknowledging the blocked change', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100))
        .thenAnswer((_) async => FulusSyncPullResponse(
              changes: [
                FulusSyncChange(
                  sequence: 6,
                  entityType: 'sale',
                  entityId: 's6',
                  operation: 'upsert',
                  payload: const {},
                  createdAt: DateTime.utc(2026, 1, 1),
                ),
              ],
              cursor: 0,
              nextCursor: 6,
              hasMore: false,
            ));

    final coordinator = FulusSyncCoordinator(
      api: api,
      cursorStore: SharedPreferencesSyncCursorStore(preferences),
      maxAutomaticBlockedAttempts: 1,
      blockedRetryBaseDelay: Duration.zero,
      now: () => DateTime.utc(2026, 1, 2),
      applyChange: (change) async {
        throw SyncCanonicalChangeApplyFailure(change, StateError('still broken'));
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<SyncCanonicalChangeBlocked>()),
    );
    expect(coordinator.cursorFor('b1'), 0);

    await coordinator.releaseBlockedChangeForRetry('b1');

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<SyncCanonicalChangeBlocked>()),
    );
    expect(coordinator.cursorFor('b1'), 0);
    verify(() => api.pullChanges(businessId: 'b1', cursor: 0, limit: 100)).called(2);
  });

}
