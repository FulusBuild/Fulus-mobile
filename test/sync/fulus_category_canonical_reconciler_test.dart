import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_category_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/category_repository.dart';

class _MockCategoryRepository extends Mock implements CategoryRepository {}

void main() {
  late _MockCategoryRepository repository;
  late FulusCategoryCanonicalReconciler reconciler;

  setUp(() {
    repository = _MockCategoryRepository();
    reconciler = FulusCategoryCanonicalReconciler(repository: repository);
  });

  test('maps authoritative category state', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'category',
        'entity_id': 'category-1',
        'operation': 'upsert',
        'row': {
          'id': 'category-1',
          'name': 'Drinks',
          'description': 'Beverages',
          'updated_at': '2026-09-15T10:00:00Z',
          'deleted_at': null,
        },
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileServerState(
          serverId: 'category-1',
          name: 'Drinks',
          description: 'Beverages',
          updatedAt: DateTime.parse('2026-09-15T10:00:00Z'),
          deletedAt: null,
        )).called(1);
  });

  test('routes canonical deletion', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'category',
        'entity_id': 'category-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileDeleted('category-2')).called(1);
  });

  test('rejects malformed updated timestamp', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'category',
        'entity_id': 'category-3',
        'operation': 'upsert',
        'row': {
          'id': 'category-3',
          'name': 'Bad',
          'updated_at': 'invalid',
        },
      },
    });

    expect(reconciler.apply(response), throwsStateError);
    verifyNever(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          updatedAt: any(named: 'updatedAt'),
        ));
  });
}
