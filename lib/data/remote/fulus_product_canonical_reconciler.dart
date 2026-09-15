import '../../domain/entities/product_stock_snapshot.dart';
import '../../domain/repositories/product_repository.dart';
import 'fulus_sync_api.dart';

class FulusProductCanonicalReconciler {
  FulusProductCanonicalReconciler({required ProductRepository repository})
      : _repository = repository;

  final ProductRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'product') {
      throw StateError(
        'Product canonical reconciler received ${response.entityType}.',
      );
    }

    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported canonical product operation: ${response.operation}',
      );
    }

    final product = _mapObject(response.data['product']);
    final rawStock = response.data['stock_levels'];
    if (rawStock is! List) {
      throw StateError('Canonical product response is missing stock_levels.');
    }

    final stockLevels = rawStock
        .map((value) => _mapStock(_mapObject(value)))
        .toList(growable: false);

    final serverId = _string(product['id']);
    final name = _string(product['name']);
    final sku = _string(product['sku']);
    final updatedAt = _date(product['updated_at']);

    await _repository.reconcileServerState(
      serverId: serverId,
      name: name,
      sku: sku,
      barcode: _nullableString(product['barcode']),
      categoryId: _nullableString(product['category_id']),
      supplierId: _nullableString(product['supplier_id']),
      costPrice: _number(product['cost_price']),
      sellingPrice: _number(product['selling_price']),
      lowStockThreshold: _integer(product['low_stock_threshold']),
      isActive: product['is_active'] == true,
      updatedAt: updatedAt,
      deletedAt: _nullableDate(product['deleted_at']),
      stockLevels: stockLevels,
    );
  }

  ProductStockSnapshot _mapStock(Map<String, dynamic> json) {
    return ProductStockSnapshot(
      locationServerId: _string(json['location_id']),
      currentStock: _integer(json['current_stock']),
      updatedAt: _date(json['updated_at']),
    );
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) {
      throw StateError('Canonical product payload contains an invalid object.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw StateError('Canonical product payload contains a missing string.');
    }
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical product payload contains an invalid number.');
  }

  int _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    throw StateError('Canonical product payload contains an invalid integer.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Canonical product payload contains an invalid date.');
    }
    return parsed;
  }

  DateTime? _nullableDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
