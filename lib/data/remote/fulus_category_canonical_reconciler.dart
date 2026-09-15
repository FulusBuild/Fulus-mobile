import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import 'fulus_sync_api.dart';

/// Entity-owned adapter for the canonical category read contract.
class FulusCategoryCanonicalReconciler {
  FulusCategoryCanonicalReconciler({required CategoryRepository repository})
      : _repository = repository;

  final CategoryRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'category') {
      throw StateError('Category canonical reconciler received ${response.entityType}.');
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported category canonical operation: ${response.operation}');
    }

    final row = response.data['row'];
    if (row is! Map) {
      throw StateError('Category canonical response is missing row data.');
    }
    final json = Map<String, dynamic>.from(row);
    final dto = CategoryResponseDto.fromJson(json);
    await _repository.reconcileServerState(
      serverId: dto.id,
      name: dto.name,
      description: dto.description,
      updatedAt: _parseDate(json['updated_at'], 'updated_at'),
      deletedAt: _parseNullableDate(json['deleted_at'], 'deleted_at'),
    );
  }

  DateTime _parseDate(Object? value, String field) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Category canonical row is missing a valid $field.');
    }
    return parsed;
  }

  DateTime? _parseNullableDate(Object? value, String field) {
    if (value == null) return null;
    return _parseDate(value, field);
  }
}
