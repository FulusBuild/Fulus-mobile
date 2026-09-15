import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fulus_mobile/data/remote/fulus_product_canonical_reconciler.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';

class _MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late _MockProductRepository repository;
  late FulusProductCanonicalReconciler reconciler;

  setUp(() {
    repository = _MockProductRepository();
    when(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          sku: any(named: 'sku'),
          barcode: any(named: 'barcode'),
          categoryId: any(named: 'categoryId'),
          supplierId: any(named: 'supplierId'),
          costPrice: any(named: 'costPrice'),
          sellingPrice: any(named: 'sellingPrice'),
          lowStockThreshold: any(named: 'lowStockThreshold'),
          isActive: any(named: 'isActive'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
          stockLevels: any(named: 'stockLevels'),
        )).thenAnswer((_) async {});
    when(() => repository.reconcileDeleted(any())).thenAnswer((_) async {});
    reconciler = FulusProductCanonicalReconciler(repository: repository);
  });

  test('maps authoritative product and stock state', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'product',
        'entity_id': 'product-1',
        'operation': 'upsert',
        'product': {
          'id': 'product-1',
          'name': 'Rice Bucket',
          'sku': 'RB-1',
          'barcode': '123',
          'category_id': 'category-1',
          'supplier_id': 'supplier-1',
          'cost_price': 1000,
          'selling_price': 1500,
          'low_stock_threshold': 5,
          'is_active': true,
          'updated_at': '2026-09-15T12:00:00Z',
          'deleted_at': null,
        },
        'stock_levels': [
          {
            'location_id': 'location-1',
            'current_stock': 17,
            'updated_at': '2026-09-15T12:01:00Z',
          },
        ],
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileServerState(
          serverId: 'product-1',
          name: 'Rice Bucket',
          sku: 'RB-1',
          barcode: '123',
          categoryId: 'category-1',
          supplierId: 'supplier-1',
          costPrice: 1000,
          sellingPrice: 1500,
          lowStockThreshold: 5,
          isActive: true,
          updatedAt: DateTime.parse('2026-09-15T12:00:00Z'),
          deletedAt: null,
          stockLevels: any(named: 'stockLevels'),
        )).called(1);
  });

  test('routes canonical deletion without outbound work', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'product',
        'entity_id': 'product-2',
        'operation': 'delete',
      },
    });

    await reconciler.apply(response);

    verify(() => repository.reconcileDeleted('product-2')).called(1);
    verifyNever(() => repository.createProduct(any()));
  });

  test('rejects malformed stock timestamp before repository write', () async {
    final response = FulusCanonicalEntityResponse.fromJson({
      'data': {
        'entity_type': 'product',
        'entity_id': 'product-3',
        'operation': 'upsert',
        'product': {
          'id': 'product-3',
          'name': 'Bucket',
          'sku': 'B-3',
          'cost_price': 100,
          'selling_price': 200,
          'low_stock_threshold': 2,
          'is_active': true,
          'updated_at': '2026-09-15T12:00:00Z',
        },
        'stock_levels': [
          {
            'location_id': 'location-1',
            'current_stock': 2,
            'updated_at': 'not-a-date',
          },
        ],
      },
    });

    expect(reconciler.apply(response), throwsStateError);
    verifyNever(() => repository.reconcileServerState(
          serverId: any(named: 'serverId'),
          name: any(named: 'name'),
          sku: any(named: 'sku'),
          barcode: any(named: 'barcode'),
          categoryId: any(named: 'categoryId'),
          supplierId: any(named: 'supplierId'),
          costPrice: any(named: 'costPrice'),
          sellingPrice: any(named: 'sellingPrice'),
          lowStockThreshold: any(named: 'lowStockThreshold'),
          isActive: any(named: 'isActive'),
          updatedAt: any(named: 'updatedAt'),
          deletedAt: any(named: 'deletedAt'),
          stockLevels: any(named: 'stockLevels'),
        ));
  });
}
