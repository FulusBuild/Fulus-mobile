import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_supplier_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/supplier_repository.dart';

class _MockSupplierRepository extends Mock implements SupplierRepository {}

void main() {
  late _MockSupplierRepository repository;
  late FulusSupplierCanonicalReconciler reconciler;

  setUp(() {
    repository = _MockSupplierRepository();
    when(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          address: any(named: 'address'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
        )).thenAnswer((_) async {});
    when(() => repository.reconcileDeleted(any())).thenAnswer((_) async {});
    reconciler = FulusSupplierCanonicalReconciler(repository: repository);
  });

  test('maps authoritative supplier state', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'supplier',
        'entity_id': 'supplier-1',
        'operation': 'upsert',
        'row': {
          'id': 'supplier-1',
          'name': 'Main Supplier',
          'phone': '+2348000000000',
          'email': 'supplier@example.com',
          'address': 'Ibadan',
          'updated_at': '2026-09-15T10:00:00Z',
          'deleted_at': null,
        },
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileServerState(
          serverId: 'supplier-1',
          name: 'Main Supplier',
          phone: '+2348000000000',
          email: 'supplier@example.com',
          address: 'Ibadan',
          updatedAt: DateTime.parse('2026-09-15T10:00:00Z'),
          deletedAt: null,
        )).called(1);
  });

  test('routes canonical deletion', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'supplier',
        'entity_id': 'supplier-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileDeleted('supplier-2')).called(1);
  });

  test('rejects malformed updated timestamp', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'supplier',
        'entity_id': 'supplier-3',
        'operation': 'upsert',
        'row': {
          'id': 'supplier-3',
          'name': 'Bad',
          'updated_at': 'invalid',
        },
      },
    });

    expect(reconciler.apply(response), throwsStateError);
    verifyNever(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          phone: any(named: 'phone'),
          email: any(named: 'email'),
          address: any(named: 'address'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
        ));
  });
}
