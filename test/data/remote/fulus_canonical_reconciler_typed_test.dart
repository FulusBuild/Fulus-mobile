import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/data/remote/fulus_canonical_reconciler_typed.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';

class _FakeCanonicalApi
    implements FulusCanonicalEntityFetcher, FulusCanonicalBatchEntityFetcher {
  final requests = <List<String>>[];

  @override
  Future<FulusCanonicalEntityResponse> fetchCanonicalEntity({
    required String businessId,
    required String entityType,
    required String entityId,
    required String deviceClientId,
  }) async => _response(entityType, entityId);

  @override
  Future<List<FulusCanonicalEntityResponse>> fetchCanonicalEntities({
    required String businessId,
    required String entityType,
    required List<String> entityIds,
    required String deviceClientId,
  }) async {
    requests.add(List<String>.from(entityIds));
    return [
      for (final id in entityIds) _response(entityType, id),
    ];
  }

  FulusCanonicalEntityResponse _response(String type, String id) {
    return FulusCanonicalEntityResponse(
      data: <String, dynamic>{
        'entity_type': type,
        'entity_id': id,
        'operation': 'upsert',
      },
    );
  }
}

void main() {
  test('batches contiguous simple entities without reordering feed sequence', () async {
    final api = _FakeCanonicalApi();
    final reconciled = <String>[];
    final sut = FulusCanonicalTypedReconciler(
      api: api,
      handlers: {
        'customer': (response) async {
          reconciled.add('customer:' + response.entityId);
        },
        'sale': (response) async {
          reconciled.add('sale:' + response.entityId);
        },
      },
    );

    await sut.reconcileChanges(
      [
        _change(1, 'customer', 'c1'),
        _change(2, 'customer', 'c2'),
        _change(3, 'sale', 's1'),
        _change(4, 'customer', 'c3'),
      ],
      businessId: 'business',
      deviceClientId: 'device',
    );

    expect(api.requests, [
      ['c1', 'c2'],
    ]);
    expect(reconciled, [
      'customer:c1',
      'customer:c2',
      'sale:s1',
      'customer:c3',
    ]);
  });

  test('never sends more than the server batch limit', () async {
    final api = _FakeCanonicalApi();
    var count = 0;
    final sut = FulusCanonicalTypedReconciler(
      api: api,
      handlers: {
        'customer': (response) async {
          count++;
        },
      },
    );

    final changes = [
      for (var i = 0; i < 205; i++)
        _change(i + 1, 'customer', 'c' + i.toString()),
    ];

    await sut.reconcileChanges(
      changes,
      businessId: 'business',
      deviceClientId: 'device',
    );

    expect(api.requests.map((request) => request.length), [100, 100, 5]);
    expect(count, 205);
  });
}

FulusSyncChange _change(int sequence, String entityType, String entityId) {
  return FulusSyncChange(
    sequence: sequence,
    entityType: entityType,
    entityId: entityId,
    operation: 'upsert',
    payload: null,
    createdAt: DateTime.utc(2026, 9, 21),
  );
}
