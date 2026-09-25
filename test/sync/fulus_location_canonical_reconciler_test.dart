import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/remote/fulus_location_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';

class _FakeLocationRepository implements LocationRepository {
  String? serverId;
  String? name;
  DateTime? updatedAt;
  DateTime? deletedAt;
  int upserts = 0;
  int deletes = 0;

  @override
  Future<void> reconcileServerState({required String serverId, required String name, required DateTime updatedAt, DateTime? deletedAt}) async {
    this.serverId = serverId;
    this.name = name;
    this.updatedAt = updatedAt;
    this.deletedAt = deletedAt;
    upserts++;
  }

  @override
  Future<void> reconcileDeleted(String serverId) async {
    this.serverId = serverId;
    deletes++;
  }

  @override
  Stream<List<Location>> watchLocations() => const Stream.empty();
  @override
  Future<Location?> getLocationById(String localId) async => null;
  @override
  Future<Location> createLocation(LocationDraft draft) => throw UnimplementedError();
  @override
  Future<Location> getOrCreateDefaultLocation({required String name}) => throw UnimplementedError();
  @override
  Future<void> markSynced({required String localId, required String serverId, String? operationId}) => throw UnimplementedError();
  @override
  Future<void> syncFromServer() => throw UnimplementedError();
}

FulusCanonicalEntityResponse _response(Map<String, dynamic> data) =>
    FulusCanonicalEntityResponse.fromJson({'data': data});

void main() {
  test('applies canonical location upsert', () async {
    final repository = _FakeLocationRepository();
    final reconciler = FulusLocationCanonicalReconciler(repository);
    await reconciler.apply(_response({
      'entity_type': 'location',
      'entity_id': 'loc-1',
      'operation': 'upsert',
      'row': {'id': 'loc-1', 'name': 'Main Location', 'updated_at': '2026-01-02T00:00:00.000Z'},
    }));
    expect(repository.upserts, 1);
    expect(repository.serverId, 'loc-1');
    expect(repository.name, 'Main Location');
    expect(repository.updatedAt, DateTime.parse('2026-01-02T00:00:00.000Z'));
  });

  test('applies canonical location delete', () async {
    final repository = _FakeLocationRepository();
    final reconciler = FulusLocationCanonicalReconciler(repository);
    await reconciler.apply(_response({'entity_type': 'location', 'entity_id': 'loc-1', 'operation': 'delete'}));
    expect(repository.deletes, 1);
    expect(repository.serverId, 'loc-1');
  });

  test('rejects a canonical response for another entity', () async {
    final repository = _FakeLocationRepository();
    final reconciler = FulusLocationCanonicalReconciler(repository);
    expect(
      () => reconciler.apply(_response({'entity_type': 'customer', 'entity_id': 'c-1', 'operation': 'upsert'})),
      throwsStateError,
    );
  });
}
