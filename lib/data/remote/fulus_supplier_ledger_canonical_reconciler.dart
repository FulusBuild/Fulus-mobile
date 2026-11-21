import '../../core/money/money.dart';
import '../../domain/entities/supplier_ledger_entry.dart';
import '../repositories/supplier_credit_repository_impl.dart';
import 'fulus_sync_api.dart';

class FulusSupplierLedgerCanonicalReconciler {
  FulusSupplierLedgerCanonicalReconciler({required SupplierCreditRepositoryImpl repository})
      : _repository = repository;

  final SupplierCreditRepositoryImpl _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'supplier_ledger') {
      throw StateError('Supplier ledger reconciler received ${response.entityType}.');
    }
    if (response.operation == 'delete') {
      throw StateError('Canonical supplier payable entries are append-only and cannot be deleted.');
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported supplier ledger operation ${response.operation}.');
    }
    final raw = response.data['row'];
    if (raw is! Map) throw StateError('Canonical supplier ledger response has no row.');
    final row = Map<String, dynamic>.from(raw);
    final entryType = switch (row['entry_type']) {
      'stock_purchase_on_credit' => SupplierLedgerEntryType.stockPurchaseOnCredit,
      'payment_made' => SupplierLedgerEntryType.paymentMade,
      _ => throw StateError('Unknown supplier ledger entry type ${row['entry_type']}.'),
    };
    await _repository.reconcileServerEntry(
      serverId: _required(row, 'id'),
      operationId: _required(row, 'operation_id'),
      supplierServerId: _required(row, 'supplier_id'),
      locationServerId: _required(row, 'location_id'),
      stockMovementServerId: _nullable(row['stock_movement_id']),
      cashDrawerShiftServerId: _nullable(row['cash_drawer_shift_id']),
      entryType: entryType,
      amount: moneyFromWire(row['amount']),
      balanceAfter: moneyFromWire(row['balance_after']),
      paymentMethod: _nullable(row['payment_method']),
      note: _nullable(row['note']),
      createdAt: _date(row['created_at']),
    );
  }

  String _required(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty) {
      throw StateError('Canonical supplier ledger row is missing $key.');
    }
    return value;
  }

  String? _nullable(Object? value) => value is String ? value : null;

  DateTime _date(Object? value) {
    final date = value is String ? DateTime.tryParse(value) : null;
    if (date == null) throw StateError('Canonical supplier ledger created_at is invalid.');
    return date;
  }
}
