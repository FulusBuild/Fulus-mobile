import '../../domain/repositories/expense_repository.dart';
import 'fulus_sync_api.dart';

/// Maps the canonical expense aggregate into the entity-owned repository.
/// Inbound reconciliation never enqueues an outbound sync task.
class FulusExpenseCanonicalReconciler {
  FulusExpenseCanonicalReconciler({required ExpenseRepository repository})
      : _repository = repository;

  final ExpenseRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'expense') {
      throw StateError(
        'Expense canonical reconciler received ${response.entityType}.',
      );
    }

    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported canonical expense operation: ${response.operation}',
      );
    }

    final row = _mapObject(response.data['row']);
    await _repository.reconcileServerState(
      serverId: _string(row['id']),
      locationServerId: _string(row['location_id']),
      categoryId: _nullableString(row['category_id']),
      description: _string(row['description']),
      amount: _number(row['amount']),
      expenseDate: _date(row['expense_date']),
      paymentMethod: _nullableString(row['payment_method']),
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
    );
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) {
      throw StateError('Canonical expense payload contains an invalid row.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw StateError('Canonical expense payload contains a missing string.');
    }
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical expense payload contains an invalid amount.');
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Canonical expense payload contains an invalid date.');
    }
    return parsed;
  }

  DateTime? _nullableDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
