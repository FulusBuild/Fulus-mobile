import '../../domain/entities/customer_ledger_entry.dart';
import '../../domain/repositories/customer_credit_repository.dart';
import 'fulus_sync_api.dart';

class FulusCustomerLedgerCanonicalReconciler {
  FulusCustomerLedgerCanonicalReconciler({required CustomerCreditRepository repository})
      : _repository = repository;

  final CustomerCreditRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'customer_ledger') {
      throw StateError(
        'Customer ledger canonical reconciler received ${response.entityType}.',
      );
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError('Unsupported canonical customer ledger operation: ${response.operation}');
    }
    final row = _mapObject(response.data['row']);
    final type = row['entry_type'];
    if (type is! String) throw StateError('Canonical customer ledger is missing entry_type.');
    await _repository.reconcileServerState(
      serverId: _string(row['id']),
      customerServerId: _string(row['customer_id']),
      saleServerId: _nullableString(row['sale_id']),
      entryType: _entryType(type),
      amount: _number(row['amount']),
      paymentMethod: _nullableString(row['payment_method']),
      note: _nullableString(row['note']),
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
    );
  }

  CustomerLedgerEntryType _entryType(String value) {
    switch (value) {
      case 'credit_sale':
        return CustomerLedgerEntryType.creditSale;
      case 'repayment':
        return CustomerLedgerEntryType.repayment;
      case 'refund_adjustment':
      case 'credit_reversal':
        // The cloud return command names the same local derived ledger
        // concept "credit_reversal". Normalize both wire representations
        // to the single local refundAdjustment type so a return-created
        // customer ledger change can never poison the pull/reconciliation loop.
        return CustomerLedgerEntryType.refundAdjustment;
      default:
        throw StateError('Unknown canonical customer ledger entry_type: $value');
    }
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) throw StateError('Canonical customer ledger row is invalid.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) throw StateError('Canonical customer ledger contains a missing string.');
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical customer ledger amount is invalid.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) throw StateError('Canonical customer ledger timestamp is invalid.');
    return parsed;
  }
}
