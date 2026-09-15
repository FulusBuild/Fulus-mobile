import '../../domain/entities/supplier.dart';
import '../../domain/repositories/supplier_repository.dart';
import 'fulus_sync_api.dart';

/// Entity-owned adapter for the canonical supplier read contract.
class FulusSupplierCanonicalReconciler {
  FulusSupplierCanonicalReconciler({required SupplierRepository repository})
      : _repository = repository;

  final SupplierRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'supplier') {
      throw StateError('Supplier canonical reconciler received ${response.entityType}.');
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported supplier canonical operation: ${response.operation}');
    }

    final row = response.data['row'];
    if (row is! Map) {
      throw StateError('Supplier canonical response is missing row data.');
    }
    final json = Map<String, dynamic>.from(row);
    final dto = SupplierResponseDto.fromJson(json);
    await _repository.reconcileServerState(
      serverId: dto.id,
      name: dto.name,
      phone: dto.phone,
      email: dto.email,
      address: dto.address,
      updatedAt: _parseDate(json['updated_at'], 'updated_at'),
      deletedAt: _parseNullableDate(json['deleted_at'], 'deleted_at'),
    );
  }

  DateTime _parseDate(Object? value, String field) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Supplier canonical row is missing a valid $field.');
    }
    return parsed;
  }

  DateTime? _parseNullableDate(Object? value, String field) {
    if (value == null) return null;
    return _parseDate(value, field);
  }
}
