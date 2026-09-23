import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_coordinator.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}

FulusSyncChange change(int sequence) => FulusSyncChange(
      sequence: sequence,
      entityType: 'customer',
      entityId: 'c$sequence',
      operation: 'upsert',
      payload: const {},
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('batch reconciliation failure never advances the durable cursor', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();

    when(() => api.pullChanges(
          businessId: 'b1',
          cursor: 0,
          limit: 100,
        )).thenAnswer(
      (_) async => FulusSyncPullResponse(
        changes: [change(1), change(2), change(3)],
        cursor: 0,
        nextCursor: 3,
        hasMore: false,
      ),
    );

    final appliedBatches = <List<int>>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      preferences: preferences,
      applyChange: (_) async {},
      applyChanges: (changes) async {
        appliedBatches.add(changes.map((e) => e.sequence).toList());
        throw StateError('local batch failed after partial work');
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<StateError>()),
    );

    expect(appliedBatches, [[1, 2, 3]]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), isNull);
  });

  test('cursor persists each applied sequence so replay after restart is bounded', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();

    when(() => api.pullChanges(
          businessId: 'b1',
          cursor: 0,
          limit: 100,
        )).thenAnswer(
      (_) async => FulusSyncPullResponse(
        changes: [change(1), change(2)],
        cursor: 0,
        nextCursor: 2,
        hasMore: false,
      ),
    );

    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      preferences: preferences,
      applyChange: (item) async {
        applied.add(item.sequence);
      },
    );

    final cursor = await coordinator.pullAndApply(businessId: 'b1');

    expect(cursor, 2);
    expect(applied, [1, 2]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), 2);
  });

  test('an out-of-order page cannot advance past a failed change', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = MockFulusSyncApi();

    when(() => api.pullChanges(
          businessId: 'b1',
          cursor: 0,
          limit: 100,
        )).thenAnswer(
      (_) async => FulusSyncPullResponse(
        changes: [change(3), change(1), change(2)],
        cursor: 0,
        nextCursor: 2,
        hasMore: false,
      ),
    );

    final applied = <int>[];
    final coordinator = FulusSyncCoordinator(
      api: api,
      preferences: preferences,
      applyChange: (item) async {
        applied.add(item.sequence);
        if (item.sequence == 1) {
          throw StateError('change 1 failed');
        }
      },
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<StateError>()),
    );

    expect(applied, [3, 1]);
    expect(preferences.getInt('fulus_sync_cursor_b1'), isNull);
  });
}
