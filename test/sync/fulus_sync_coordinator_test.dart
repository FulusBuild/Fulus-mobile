import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_coordinator.dart';
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
    final coordinator = FulusSyncCoordinator(api: api, preferences: preferences, applyChange: (change) async => applied.add(change.sequence));
    final cursor = await coordinator.pullAndApply(businessId: 'b1');
    expect(cursor, 2);
    expect(applied, [1, 2]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 2);
  });

  test('does not advance cursor past a failed change', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 1});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();
    when(() => api.pullChanges(businessId: 'b1', cursor: 1, limit: 100)).thenAnswer((_) async => FulusSyncPullResponse(
      changes: [FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1))],
      cursor: 1, nextCursor: 2, hasMore: false,
    ));
    final coordinator = FulusSyncCoordinator(api: api, preferences: preferences, applyChange: (_) async => throw StateError('apply failed'));
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
      preferences: preferences,
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
      preferences: preferences,
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
      preferences: preferences,
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
      api: api, preferences: preferences,
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
      preferences: preferences,
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
      preferences: preferences,
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
      preferences: preferences,
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
      preferences: preferences,
      applyChange: (_) async {},
    );

    await coordinator.resetCursor('b1');

    expect(coordinator.cursorFor('b1'), 0);
    expect(coordinator.cursorFor('b2'), 3);
  });
}
