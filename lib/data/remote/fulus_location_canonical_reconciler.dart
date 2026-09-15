import '../../domain/repositories/location_repository.dart';
import 'fulus_canonical_reconciler_typed.dart';

/// Translates canonical location state into the entity-owned repository
/// contract. Transport and local persistence remain separate.
class FulusLocationCanonicalReconciler {
  const FulusLocationCanonicalReconciler(this._repository);

  final LocationRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'location') {
      throw StateError('Expected location canonical state.');
    }

    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported location canonical operation: ${response.operation}');
    }

    final row = response.data['row'];
    if (row is! Map<String, dynamic>) {
      throw StateError('Canonical location response is missing row data.');
    }

    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String) {
      throw StateError('Canonical location row has invalid identity fields.');
    }

    await _repository.reconcileServerState(
      serverId: id,
      name: name,
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
    );
  }

  DateTime _date(Object? value) {
    if (value is! String) throw StateError('Canonical location timestamp is missing.');
    return DateTime.parse(value);
  }

  DateTime? _nullableDate(Object? value) => value is String ? DateTime.parse(value) : null;
}
