import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_coordinator.dart';

class FakeFulusSyncApi extends FulusSyncApi {
  FakeFulusSyncApi(this.pages) : super(client: throw UnimplementedError(), functionBaseUrl: '');

  final List<FulusSyncPullResponse> pages;
  int calls = 0;

  @override
  Future<FulusSyncPullResponse> pullChanges({
    required String businessId,
    int cursor = 0,
    int limit = 100,
  }) async => pages[calls++];
}

void main() {
  test('persists cursor only after every change is applied', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final api = FakeFulusSyncApi([
      FulusSyncPullResponse(
        changes: [
          FulusSyncChange(sequence: 1, entityType: 'customer', entityId: 'c1', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
          FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
        ],
        cursor: 0,
        nextCursor: 2,
        hasMore: false,
      ),
    ]);
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
  });

  test('does not advance cursor past a failed change', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_cursor_b1': 1});
    final preferences = await SharedPreferences.getInstance();
    final api = FakeFulusSyncApi([
      FulusSyncPullResponse(
        changes: [
          FulusSyncChange(sequence: 2, entityType: 'customer', entityId: 'c2', operation: 'upsert', payload: const {}, createdAt: DateTime.utc(2026, 1, 1)),
        ],
        cursor: 1,
        nextCursor: 2,
        hasMore: false,
      ),
    ]);
    final coordinator = FulusSyncCoordinator(
      api: api,
      preferences: preferences,
      applyChange: (_) async => throw StateError('apply failed'),
    );

    await expectLater(
      coordinator.pullAndApply(businessId: 'b1'),
      throwsA(isA<StateError>()),
    );
    expect(preferences.getInt('fulus_sync_cursor_b1'), 1);
  });
}
