import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_expense_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/expense_repository.dart';

class _MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  late _MockExpenseRepository repository;
  late FulusExpenseCanonicalReconciler reconciler;

  setUp(() {
    repository = _MockExpenseRepository();
    reconciler = FulusExpenseCanonicalReconciler(repository: repository);
  });

  test('maps authoritative expense state', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'expense',
        'entity_id': 'expense-1',
        'operation': 'upsert',
        'row': {
          'id': 'expense-1',
          'location_id': 'location-1',
          'category_id': 'category-1',
          'description': 'Transport',
          'amount': 4500,
          'expense_date': '2026-09-15T10:00:00Z',
          'payment_method': 'cash',
          'created_at': '2026-09-15T09:00:00Z',
          'updated_at': '2026-09-15T10:00:00Z',
          'deleted_at': null,
        },
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileServerState(
          serverId: 'expense-1',
          locationServerId: 'location-1',
          categoryId: 'category-1',
          description: 'Transport',
          amount: 4500,
          expenseDate: DateTime.parse('2026-09-15T10:00:00Z'),
          paymentMethod: 'cash',
          createdAt: DateTime.parse('2026-09-15T09:00:00Z'),
          updatedAt: DateTime.parse('2026-09-15T10:00:00Z'),
          deletedAt: null,
        )).called(1);
  });

  test('routes canonical deletion', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'expense',
        'entity_id': 'expense-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileDeleted('expense-2')).called(1);
  });

  test('rejects malformed canonical expense timestamp', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'expense',
        'entity_id': 'expense-3',
        'operation': 'upsert',
        'row': {
          'id': 'expense-3',
          'location_id': 'location-1',
          'description': 'Bad',
          'amount': 100,
          'expense_date': '2026-09-15T10:00:00Z',
          'created_at': '2026-09-15T09:00:00Z',
          'updated_at': 'invalid',
        },
      },
    });

    expect(reconciler.apply(response), throwsStateError);
    verifyNever(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          locationServerId: any(named: 'locationServerId'),
          description: any(named: 'description'),
          amount: any(named: 'amount'),
          expenseDate: any(named: 'expenseDate'),
          createdAt: any(named: 'createdAt'),
          updatedAt: any(named: 'updatedAt'),
        ));
  });
}
