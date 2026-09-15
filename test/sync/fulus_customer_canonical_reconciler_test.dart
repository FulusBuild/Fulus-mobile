import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_customer_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/customer_repository.dart';

class _MockCustomerRepository extends Mock implements CustomerRepository {}

void main() {
  late _MockCustomerRepository repository;
  late FulusCustomerCanonicalReconciler reconciler;

  setUp(() {
    repository = _MockCustomerRepository();
    reconciler = FulusCustomerCanonicalReconciler(repository: repository);
  });

  test('upserts server-authoritative customer fields without outbound sync', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'customer',
        'entity_id': 'server-customer-1',
        'operation': 'upsert',
        'row': {
          'id': 'server-customer-1',
          'name': 'Server Customer',
          'phone': '+2348000000000',
          'email': 'customer@example.com',
          'address': 'Ibadan',
          'notes': 'from another device',
          'outstanding_balance': 12500.0,
          'duplicate_warning': null,
          'updated_at': '2026-09-15T12:00:00.000Z',
        },
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileServerState(
          serverId: 'server-customer-1',
          name: 'Server Customer',
          phone: '+2348000000000',
          email: 'customer@example.com',
          address: 'Ibadan',
          notes: 'from another device',
          outstandingBalance: 12500.0,
          duplicateWarning: null,
          updatedAt: DateTime.parse('2026-09-15T12:00:00.000Z'),
        )).called(1);
    verifyNever(() => repository.createCustomer(any()));
    verifyNever(() => repository.markSynced(
          localId: any(named: 'localId'),
          serverId: any(named: 'serverId'),
          duplicateWarning: any(named: 'duplicateWarning'),
        ));
  });

  test('routes canonical delete to repository without enqueueing a write', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'customer',
        'entity_id': 'server-customer-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileDeleted('server-customer-2')).called(1);
    verifyNever(() => repository.archiveCustomer(any()));
  });

  test('rejects a malformed customer canonical row', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'customer',
        'entity_id': 'server-customer-3',
        'operation': 'upsert',
        'row': {'id': 'server-customer-3', 'name': 'Missing timestamp'},
      },
    });

    expect(reconciler.apply(response), throwsStateError);
    verifyNever(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          address: any(named: 'address'),
          notes: any(named: 'notes'),
          outstandingBalance: any(named: 'outstandingBalance'),
          duplicateWarning: any(named: 'duplicateWarning'),
          updatedAt: any(named: 'updatedAt'),
        ));
  });
}
