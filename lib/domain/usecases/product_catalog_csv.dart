import '../../core/money/money.dart';
import '../entities/product.dart';

/// Builds an active, current-location product export using stable CSV columns.
/// Formula-injection protection is applied by CsvExportService at serialization.
abstract final class ProductCatalogCsv {
  static const headers = <String>[
    'Name',
    'SKU',
    'Barcode',
    'Cost price',
    'Selling price',
    'Stock on hand',
    'Unit',
    'Low stock threshold',
    'Tracks stock',
  ];

  static List<List<Object?>> rows(List<ProductWithStock> products) => [
    for (final item in products)
      [
        item.product.name,
        item.product.sku,
        item.product.barcode,
        moneyToMajor(item.product.costPrice).toStringAsFixed(2),
        moneyToMajor(item.product.sellingPrice).toStringAsFixed(2),
        item.currentStock,
        item.product.unit,
        item.product.lowStockThreshold,
        item.product.tracksStock,
      ],
  ];
}
