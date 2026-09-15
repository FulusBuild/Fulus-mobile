import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/remote/fulus_canonical_reconciler_typed.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';

class _FakeApi implements FulusCanonicalEntityFetcher {
  _FakeApi(this.response);

  final FulusCanonicalEntityResponse response;

  @override
  Future<FulusCanonicalEntityResponse> fetchCanonicalEntity({
    required String businessId,
    required String entityType,
    required String entityId,
    required String deviceClientId,
  }) async => response;
}

void main() {
  test('routes canonical state to the typed entity handler', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'customer',
        'entity_id': 'customer-1',
        'operation': 'upsert',
        'row': {'id': 'customer-1'},
      },
    });
    var called = false;
    final reconciler = FulusCanonicalTypedReconciler(
      api: _FakeApi(response),
      handlers: {
        'customer': (value) async {
          called = value.entityId == 'customer-1';
        },
      },
    );

    await reconciler.reconcile(
      FulusSyncChange(
        sequence: 1,
        entityType: 'customer',
        entityId: 'customer-1',
        operation: 'upsert',
        payload: const {},
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      businessId: 'business-1',
      deviceClientId: 'device-1',
    );

    expect(called, isTrue);
  });

  test('unknown entities fail before canonical fetch', () async {
    var fetched = false;
    final api = _FakeApi(FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'customer',
        'entity_id': 'customer-1',
        'operation': 'upsert',
      },
    }));
    final reconciler = FulusCanonicalTypedReconciler(
      api: api,
      handlers: const {},
    );

    expect(
      () async {
        fetched = true;
        await reconciler.reconcile(
          FulusSyncChange(
            sequence: 1,
            entityType: 'customer',
            entityId: 'customer-1',
            operation: 'upsert',
            payload: const {},
            createdAt: DateTime.utc(2026, 1, 1),
          ),
          businessId: 'business-1',
          deviceClientId: 'device-1',
        );
      },
      throwsStateError,
    );
    expect(fetched, isFalse);
  });
}
