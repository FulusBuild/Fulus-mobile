import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import 'fulus_sync_api.dart';

/// Entity-owned adapter for the canonical customer read contract.
///
/// The transport layer returns JSON, but this adapter is the only place that
/// interprets the customer payload. Persistence remains owned by
/// CustomerRepository, so server-originated changes cannot enqueue outbound
/// sync work accidentally.
class FulusCustomerCanonicalReconciler {
  FulusCustomerCanonicalReconciler({required CustomerRepository repository})
      : _repository = repository;

  final CustomerRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'customer') {
      throw StateError(
        'Customer canonical reconciler received ${response.entityType}.',
      );
    }

    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }

    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported customer canonical operation: ${response.operation}',
      );
    }

    final row = response.data['row'];
    if (row is! Map) {
      throw StateError('Customer canonical response is missing row data.');
    }

    final dto = CustomerResponseDto.fromJson(
      Map<String, dynamic>.from(row),
    );
    await _repository.reconcileServerState(
      serverId: dto.id,
      name: dto.name,
      phone: dto.phone,
      email: dto.email,
      address: dto.address,
      notes: dto.notes,
      outstandingBalance: dto.outstandingBalance,
      duplicateWarning: dto.duplicateWarning,
      updatedAt: _parseUpdatedAt(row),
    );
  }

  DateTime _parseUpdatedAt(Map<String, dynamic> row) {
    final value = row['updated_at'];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw StateError('Customer canonical row is missing a valid updated_at.');
  }
}
