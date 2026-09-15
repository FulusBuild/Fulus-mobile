import '../../domain/repositories/location_repository.dart';
import 'fulus_sync_api.dart';

/// Translates canonical location state into the entity-owned repository contract.
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

    final raw = response.data['row'];
    if (raw is! Map) {
      throw StateError('Canonical location response is missing row data.');
    }
    final row = Map<String, dynamic>.from(raw);
    final id = row['id'];
    final name = row['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
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
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical location timestamp is invalid.');
    return parsed;
  }

  DateTime? _nullableDate(Object? value) {
    if (value == null) return null;
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical location deleted_at is invalid.');
    return parsed;
  }
}
