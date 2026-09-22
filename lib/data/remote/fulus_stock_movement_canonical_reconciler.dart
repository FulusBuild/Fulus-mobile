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
    final type = _movementType(row);
    final quantity = _nullableInt(row['quantity']) ??
        (_nullableInt(row['quantity_delta'])?.abs());
    final newQuantity = _nullableInt(row['new_quantity']) ??
        (type == StockMovementType.adjustment
            ? _nullableInt(row['current_stock'])
            : null);

    await _repository.reconcileServerState(
      serverId: _string(row['id']),
      productServerId: _string(row['product_id']),
      locationServerId: _string(row['location_id']),
      toLocationServerId: _nullableString(row['to_location_id']),
      movementType: type,
      quantity: quantity,
      newQuantity: newQuantity,
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

  StockMovementType _movementType(Map<String, dynamic> row) {
    final raw = row['movement_type'];
    if (raw is String && raw.isNotEmpty) {
      return StockMovementType.fromWireValue(raw);
    }

    // Backward compatibility for retained change-feed rows created before
    // the server started emitting the richer movement_type contract.
    final reason = row['reason']?.toString().toLowerCase() ?? '';
    if (reason.startsWith('sale ')) return StockMovementType.sale;

    final delta = _nullableInt(row['quantity_delta']);
    if (delta == null || delta == 0) {
      throw StateError(
        'Canonical stock movement payload is missing movement_type and quantity_delta.',
      );
    }
    return delta > 0
        ? StockMovementType.stockIn
        : StockMovementType.stockOut;
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
