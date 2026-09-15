import '../../domain/entities/expense_category.dart';
import '../../domain/repositories/expense_category_repository.dart';
import 'fulus_sync_api.dart';

class FulusExpenseCategoryCanonicalReconciler {
  FulusExpenseCategoryCanonicalReconciler({required ExpenseCategoryRepository repository})
      : _repository = repository;

  final ExpenseCategoryRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'expense_category') {
      throw StateError(
        'Expense category canonical reconciler received ${response.entityType}.',
      );
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported canonical expense category operation: ${response.operation}',
      );
    }
    final row = _mapObject(response.data['row']);
    final dto = ExpenseCategoryResponseDto.fromJson(row);
    await _repository.reconcileServerState(
      serverId: dto.id,
      name: dto.name,
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
    );
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) {
      throw StateError('Canonical expense category payload contains an invalid row.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Canonical expense category payload contains an invalid date.');
    }
    return parsed;
  }

  DateTime? _nullableDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
