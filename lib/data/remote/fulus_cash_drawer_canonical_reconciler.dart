import '../../domain/repositories/cash_drawer_shift_repository.dart';
import 'fulus_sync_api.dart';

/// Maps canonical cash-drawer state into the entity-owned repository.
class FulusCashDrawerCanonicalReconciler {
  FulusCashDrawerCanonicalReconciler({required CashDrawerShiftRepository repository})
      : _repository = repository;

  final CashDrawerShiftRepository _repository;

  Future<void> apply(FulusCanonicalEntityResponse response) async {
    if (response.entityType != 'cash_drawer_shift') {
      throw StateError(
        'Cash drawer canonical reconciler received ${response.entityType}.',
      );
    }
    if (response.operation == 'delete') {
      await _repository.reconcileDeleted(response.entityId);
      return;
    }
    if (response.operation != 'upsert') {
      throw StateError(
        'Unsupported canonical cash drawer operation: ${response.operation}',
      );
    }

    final row = _mapObject(response.data['row']);
    await _repository.reconcileServerState(
      serverId: _string(row['id']),
      cashierUserId: _string(row['cashier_id']),
      locationServerId: _string(row['location_id']),
      openedAt: _date(row['opened_at']),
      closedAt: _nullableDate(row['closed_at']),
      openingCash: _number(row['opening_cash']),
      closingCash: _nullableNumber(row['closing_cash']),
      cashDifference: _nullableNumber(row['cash_difference']),
      closingNote: _nullableString(row['closing_note']),
      closingSummaryLocked: row['closing_summary_locked'] == true,
      updatedAt: _date(row['updated_at']),
    );
  }

  Map<String, dynamic> _mapObject(Object? value) {
    if (value is! Map) {
      throw StateError('Canonical cash drawer payload contains an invalid row.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _string(Object? value) {
    if (value is! String || value.isEmpty) {
      throw StateError('Canonical cash drawer payload contains a missing string.');
    }
    return value;
  }

  String? _nullableString(Object? value) => value is String ? value : null;

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    throw StateError('Canonical cash drawer payload contains an invalid number.');
  }

  double? _nullableNumber(Object? value) => value is num ? value.toDouble() : null;

  DateTime _date(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw StateError('Canonical cash drawer payload contains an invalid date.');
    }
    return parsed;
  }

  DateTime? _nullableDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
