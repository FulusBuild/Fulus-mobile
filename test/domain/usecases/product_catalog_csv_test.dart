import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/money/money.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/domain/usecases/product_catalog_csv.dart';

void main() {
  test('exports product identity, money, stock and tracking fields', () {
    final product = Product(
      localId: 'p1',
      locationId: 'loc1',
      name: '=1+1',
      sku: 'SKU-1',
      barcode: '12345',
      costPrice: moneyFromMajor(2.5),
      sellingPrice: moneyFromMajor(4.75),
      lowStockThreshold: 3,
      isActive: true,
      tracksStock: false,
      unit: 'piece',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect(
      ProductCatalogCsv.headers,
      containsAll(['Name', 'Stock on hand', 'Tracks stock']),
    );
    expect(
      ProductCatalogCsv.rows([
        ProductWithStock(product: product, currentStock: 8),
      ]),
      [
        ['=1+1', 'SKU-1', '12345', '2.50', '4.75', 8, 'piece', 3, false],
      ],
    );
  });
}
