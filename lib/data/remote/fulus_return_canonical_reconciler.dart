import '../../domain/entities/return_canonical_state.dart';
import '../../domain/repositories/return_canonical_repository.dart';
import 'fulus_sync_api.dart';

class FulusReturnCanonicalReconciler {
  FulusReturnCanonicalReconciler({required ReturnCanonicalRepository repository})
      : _repository = repository;

  final ReturnCanonicalRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'return') {
      throw StateError('Return canonical reconciler received ${response.entityType}.');
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported canonical return operation: ${response.operation}');
    }

    final row = _object(response.data['row']);
    final rawItems = response.data['return_items'];
    if (rawItems is! List) {
      throw StateError('Canonical return response is missing return_items.');
    }

    final state = ReturnCanonicalState(
      serverId: _string(row['id']),
      originalSaleServerId: _string(row['original_sale_id']),
      status: _string(row['status']),
      returnReason: _string(row['return_reason']),
      refundAmount: _number(row['refund_amount']),
      refundMethod: _string(row['refund_method']),
      inventoryRestored: row['inventory_restored'] == true,
      isVoid: row['is_void'] == true,
      items: rawItems.map((value) {
        final item = _object(value);
        return ReturnCanonicalItem(
          serverId: _string(item['id']),
          productServerId: _string(item['product_id']),
          quantity: _integer(item['quantity']),
        );
      }).toList(growable: false),
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      completedAt: _nullableDate(row['completed_at']),
    );

    if (state.serverId != response.entityId) {
      throw StateError('Canonical return response does not match the change.');
    }
    await _repository.reconcileServerState(state);
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw StateError('Canonical return payload contains an invalid object.');
    return Map<String, dynamic>.from(value);
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) throw StateError('Canonical return payload contains a missing string.');
    return value;
  }

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical return payload contains an invalid number.');
  }

  int _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    throw StateError('Canonical return payload contains an invalid integer.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical return payload contains an invalid date.');
    return parsed;
  }

  DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);
}
