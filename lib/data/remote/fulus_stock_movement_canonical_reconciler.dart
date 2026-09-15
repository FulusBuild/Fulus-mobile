import '../../domain/entities/stock_movement.dart';
import '../../domain/repositories/stock_movement_repository.dart';
import 'fulus_sync_api.dart';

class FulusStockMovementCanonicalReconciler {
  FulusStockMovementCanonicalReconciler({required StockMovementRepository repository})
      : _repository = repository;

  final StockMovementRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'stock_movement') {
      throw StateError(
        'Stock movement canonical reconciler received ${response.entityType}.',
      );
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported canonical stock movement operation: ${response.operation}',
      );
    }
    final row = _mapObject(response.data['row']);
    final type = row['movement_type'];
    if (type is! String) {
      throw StateError('Canonical stock movement payload is missing movement_type.');
    }
    await _repository.reconcileServerState(
      serverId: _string(row['id']),
      productServerId: _string(row['product_id']),
      locationServerId: _string(row['location_id']),
      toLocationServerId: _nullableString(row['to_location_id']),
      movementType: StockMovementType.fromWireValue(type),
      quantity: _nullableInt(row['quantity']),
      newQuantity: _nullableInt(row['new_quantity']),
      reason: _nullableString(row['reason']),
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
    );
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) throw StateError('Canonical stock movement row is invalid.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) throw StateError('Canonical stock movement contains a missing string.');
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    throw StateError('Canonical stock movement contains an invalid integer.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical stock movement contains an invalid date.');
    return parsed;
  }

  DateTime? _nullableDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
}
