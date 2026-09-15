import '../../domain/entities/sale_canonical_state.dart';
import '../../domain/repositories/sale_canonical_repository.dart';
import 'fulus_sync_api.dart';

class FulusSaleCanonicalReconciler {
  FulusSaleCanonicalReconciler({required SaleCanonicalRepository repository})
      : _repository = repository;

  final SaleCanonicalRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'sale') {
      throw StateError('Sale canonical reconciler received ${response.entityType}.');
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported canonical sale operation: ${response.operation}');
    }

    final sale = _object(response.data['sale'], 'sale');
    final rawItems = response.data['sale_items'];
    final rawPayments = response.data['sale_payments'];
    if (rawItems is! List || rawPayments is! List) {
      throw StateError('Canonical sale response is missing aggregate children.');
    }

    final state = SaleCanonicalState(
      serverId: _string(sale['id']),
      clientReference: _nullableString(sale['client_reference']) ?? '',
      invoiceNumber: _nullableString(sale['invoice_number']),
      customerServerId: _nullableString(sale['customer_id']),
      locationServerId: _string(sale['location_id']),
      cashierUserId: _nullableString(sale['cashier_user_id']),
      saleDate: _date(sale['sale_date']),
      subtotal: _number(sale['subtotal']),
      discount: _number(sale['discount']),
      tax: _number(sale['tax']),
      total: _number(sale['total']),
      amountPaid: _number(sale['amount_paid']),
      paymentMethod: _nullableString(sale['payment_method']),
      notes: _nullableString(sale['notes']),
      items: rawItems.map((value) => _mapItem(_object(value, 'sale item'))).toList(growable: false),
      payments: rawPayments.map((value) => _mapPayment(_object(value, 'sale payment'))).toList(growable: false),
      createdAt: _date(sale['created_at']),
      updatedAt: _date(sale['updated_at']),
      deletedAt: _nullableDate(sale['deleted_at']),
    );

    if (state.serverId != response.entityId) {
      throw StateError('Canonical sale response does not match the change.');
    }
    await _repository.reconcileServerState(state);
  }

  SaleCanonicalItem _mapItem(Map<String, dynamic> row) {
    return SaleCanonicalItem(
      serverId: _string(row['id']),
      productServerId: _string(row['product_id']),
      quantity: _integer(row['quantity']),
      unitPrice: _number(row['unit_price']),
      costPriceAtSale: _number(row['cost_price_at_sale']),
      lineTotal: _number(row['line_total']),
    );
  }

  SaleCanonicalPayment _mapPayment(Map<String, dynamic> row) {
    return SaleCanonicalPayment(
      serverId: _string(row['id']),
      method: _string(row['method']),
      amount: _number(row['amount']),
      recordedAt: _date(row['recorded_at']),
    );
  }

  Map<String, dynamic> _object(Object? value, String label) {
    if (value is! Map) throw StateError('Canonical $label payload is invalid.');
    return Map<String, dynamic>.from(value);
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) throw StateError('Canonical sale payload contains a missing string.');
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical sale payload contains an invalid number.');
  }

  int _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.toInt()) return value.toInt();
    throw StateError('Canonical sale payload contains an invalid integer.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical sale payload contains an invalid date.');
    return parsed;
  }

  DateTime? _nullableDate(Object? value) {
    if (value == null) return null;
    return _date(value);
  }
}
