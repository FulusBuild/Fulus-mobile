import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/product.dart';
import 'package:fulus_mobile/features/stock/application/stock_providers.dart';

void main() {
  final now = DateTime(2026, 11, 20);

  ProductWithStock product(String id, int stock, {bool tracksStock = true}) =>
      ProductWithStock(
        product: Product(
          localId: id,
          name: id,
          sku: id,
          costPrice: 100,
          sellingPrice: 200,
          lowStockThreshold: 5,
          isActive: true,
          tracksStock: tracksStock,
          createdAt: now,
          updatedAt: now,
        ),
        currentStock: stock,
      );

  test(
    'low-stock filter includes zero and threshold quantities consistently',
    () {
      final products = [
        product('zero', 0),
        product('below', 2),
        product('at-threshold', 5),
        product('healthy', 6),
        product('untracked', 0, tracksStock: false),
      ];
      final count = products.where((item) => item.isLowStock).length;
      final filtered = applyStockFilter(
        products,
        const StockFilterState(lowStockOnly: true),
      );

      expect(count, 3);
      expect(filtered.map((item) => item.product.localId), [
        'at-threshold',
        'below',
        'zero',
      ]);
    },
  );
}
