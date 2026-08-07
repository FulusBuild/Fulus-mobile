import 'package:fulus_mobile/domain/entities/category.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/domain/entities/supplier.dart';
import 'package:fulus_mobile/domain/repositories/category_repository.dart';
import 'package:fulus_mobile/domain/repositories/product_repository.dart';
import 'package:fulus_mobile/domain/repositories/supplier_repository.dart';
import 'package:fulus_mobile/domain/usecases/import_products_from_csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProductRepository extends Mock implements ProductRepository {}

class MockCategoryRepository extends Mock implements CategoryRepository {}

class MockSupplierRepository extends Mock implements SupplierRepository {}

void main() {
  late MockProductRepository productRepository;
  late MockCategoryRepository categoryRepository;
  late MockSupplierRepository supplierRepository;
  late ImportProductsFromCsv importUseCase;

  const locationId = 'loc-1';
  final now = DateTime(2026, 1, 1);

  Product fakeProduct(ProductDraft draft, {String localId = 'p-new'}) {
    return draft.toProductEntity(localId: localId);
  }

  Category fakeCategory(String name, {String localId = 'c-new'}) {
    return Category(localId: localId, name: name, createdAt: now, updatedAt: now);
  }

  setUpAll(() {
    registerFallbackValue(const ProductDraft(
      name: 'fallback',
      sku: 'fallback',
      costPrice: 0,
      sellingPrice: 0,
      locationId: locationId,
    ));
    registerFallbackValue(const CategoryDraft(name: 'fallback'));
    registerFallbackValue(const SupplierDraft(name: 'fallback'));
  });

  setUp(() {
    productRepository = MockProductRepository();
    categoryRepository = MockCategoryRepository();
    supplierRepository = MockSupplierRepository();
    importUseCase = ImportProductsFromCsv(
      productRepository: productRepository,
      categoryRepository: categoryRepository,
      supplierRepository: supplierRepository,
    );

    when(() => productRepository.getAllSkus()).thenAnswer((_) async => <String>{});
    when(() => productRepository.getAllBarcodes()).thenAnswer((_) async => <String>{});
    when(() => categoryRepository.watchCategories()).thenAnswer((_) => Stream.value(const []));
    when(() => supplierRepository.watchSuppliers()).thenAnswer((_) => Stream.value(const []));
    when(() => productRepository.createProduct(any())).thenAnswer(
      (invocation) async => fakeProduct(invocation.positionalArguments.first as ProductDraft),
    );
  });

  test('creates every valid row and reports the right success count', () async {
    const csv = 'name,sku,selling_price\nRice,R1,2500\nBeans,B1,900';

    final result = await importUseCase(csvContent: csv, locationId: locationId);

    expect(result.successCount, 2);
    expect(result.errorCount, 0);
    expect(result.totalRows, 2);
    verify(() => productRepository.createProduct(any())).called(2);
  });

  test('a header-rejected file never touches any repository', () async {
    const csv = 'name,sku\nRice,R1'; // missing selling_price

    final result = await importUseCase(csvContent: csv, locationId: locationId);

    expect(result.successCount, 0);
    expect(result.errors.single.message, contains('selling_price'));
    verifyNever(() => productRepository.getAllSkus());
    verifyNever(() => productRepository.createProduct(any()));
  });

  test('creates a new category by name and links the product to it', () async {
    when(() => categoryRepository.createCategory(any())).thenAnswer(
      (invocation) async => fakeCategory((invocation.positionalArguments.first as CategoryDraft).name),
    );
    const csv = 'name,sku,selling_price,category\nRice,R1,2500,Grains';

    await importUseCase(csvContent: csv, locationId: locationId);

    final captured = verify(() => productRepository.createProduct(captureAny())).captured;
    expect((captured.single as ProductDraft).categoryId, 'c-new');
    verify(() => categoryRepository.createCategory(any())).called(1);
  });

  test('two rows with the same new category name only create the category once', () async {
    when(() => categoryRepository.createCategory(any())).thenAnswer(
      (invocation) async => fakeCategory((invocation.positionalArguments.first as CategoryDraft).name),
    );
    const csv = 'name,sku,selling_price,category\nRice,R1,2500,Grains\nBeans,B1,900,Grains';

    await importUseCase(csvContent: csv, locationId: locationId);

    verify(() => categoryRepository.createCategory(any())).called(1);
  });

  test('reuses an existing category rather than creating a duplicate', () async {
    when(() => categoryRepository.watchCategories()).thenAnswer(
      (_) => Stream.value([Category(localId: 'existing-grains', name: 'Grains', createdAt: now, updatedAt: now)]),
    );
    const csv = 'name,sku,selling_price,category\nRice,R1,2500,grains'; // different case on purpose

    await importUseCase(csvContent: csv, locationId: locationId);

    verifyNever(() => categoryRepository.createCategory(any()));
    final captured = verify(() => productRepository.createProduct(captureAny())).captured;
    expect((captured.single as ProductDraft).categoryId, 'existing-grains');
  });

  test('a create failure on one row is recorded as an error without blocking the rest', () async {
    when(() => productRepository.createProduct(any())).thenAnswer((invocation) async {
      final draft = invocation.positionalArguments.first as ProductDraft;
      if (draft.sku == 'BAD') {
        throw StateError('local database write failed');
      }
      return fakeProduct(draft);
    });
    const csv = 'name,sku,selling_price\nBroken,BAD,100\nFine,FINE,200';

    final result = await importUseCase(csvContent: csv, locationId: locationId);

    expect(result.successCount, 1);
    expect(result.errorCount, 1);
    expect(result.createdProductLocalIds, hasLength(1));
  });
}
