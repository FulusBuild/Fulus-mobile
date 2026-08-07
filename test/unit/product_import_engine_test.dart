import 'package:fulus_mobile/domain/usecases/product_import_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ProductImportEngine();
  const headers = ['name', 'sku', 'selling_price', 'cost_price', 'barcode', 'category', 'supplier', 'initial_stock', 'low_stock_threshold'];

  Map<String, String> row({
    String name = 'Rice 5kg',
    String sku = 'RICE-5KG',
    String sellingPrice = '2500',
    String costPrice = '',
    String barcode = '',
    String category = '',
    String supplier = '',
    String initialStock = '',
    String lowStockThreshold = '',
  }) {
    return {
      'name': name,
      'sku': sku,
      'selling_price': sellingPrice,
      'cost_price': costPrice,
      'barcode': barcode,
      'category': category,
      'supplier': supplier,
      'initial_stock': initialStock,
      'low_stock_threshold': lowStockThreshold,
    };
  }

  group('header validation', () {
    test('rejects the whole file when a required column is missing', () {
      final plan = engine.validate(
        headers: const ['name', 'sku'], // no selling_price
        rows: [row()],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.isRejected, isTrue);
      expect(plan.headerErrors.single.message, contains('selling_price'));
      expect(plan.rowsToCreate, isEmpty);
    });

    test('header matching is case-insensitive', () {
      final plan = engine.validate(
        headers: const ['Name', 'SKU', 'Selling_Price'],
        rows: [
          {'Name': 'Rice', 'SKU': 'R1', 'Selling_Price': '100'},
        ],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.isRejected, isFalse);
      expect(plan.rowsToCreate, hasLength(1));
    });
  });

  group('row validation', () {
    test('a fully valid row becomes a row to create with defaults applied', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row()],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowErrors, isEmpty);
      final created = plan.rowsToCreate.single;
      expect(created.name, 'Rice 5kg');
      expect(created.sku, 'RICE-5KG');
      expect(created.sellingPrice, 2500);
      expect(created.costPrice, 0); // default
      expect(created.initialStock, 0); // default
      expect(created.lowStockThreshold, 10); // default
    });

    test('missing name is a row error, not a thrown exception', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(name: '')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate, isEmpty);
      expect(plan.rowErrors.single.field, 'name');
    });

    test('a SKU already in the existing catalog is rejected', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(sku: 'ALREADY-EXISTS')],
        existingSkus: const {'ALREADY-EXISTS'},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate, isEmpty);
      expect(plan.rowErrors.single.field, 'sku');
    });

    test('two rows in the same file sharing a SKU: first wins, second rejected', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(sku: 'DUP'), row(sku: 'DUP', name: 'Second one')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate, hasLength(1));
      expect(plan.rowsToCreate.single.name, 'Rice 5kg');
      expect(plan.rowErrors, hasLength(1));
      expect(plan.rowErrors.single.row, 2);
    });

    test('an invalid selling_price is one error, not two', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(sellingPrice: 'not-a-number')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowErrors, hasLength(1));
      expect(plan.rowErrors.single.message, contains('not a valid number'));
    });

    test('a blank selling_price is reported as required, exactly once', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(sellingPrice: '')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowErrors, hasLength(1));
      expect(plan.rowErrors.single.message, 'Selling price is required.');
    });

    test('a negative selling_price is rejected', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(sellingPrice: '-5')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate, isEmpty);
      expect(plan.rowErrors.single.message, contains('0 or greater'));
    });

    test('accepts a decimal-looking integer field, matching the more lenient backend parse', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(initialStock: '10.0')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowErrors, isEmpty);
      expect(plan.rowsToCreate.single.initialStock, 10);
    });

    test('a duplicate barcode against the existing catalog is rejected', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(barcode: '600123')],
        existingSkus: const {},
        existingBarcodes: const {'600123'},
      );

      expect(plan.rowsToCreate, isEmpty);
      expect(plan.rowErrors.single.field, 'barcode');
    });

    test('one bad row does not block a good row elsewhere in the same file', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(name: ''), row(sku: 'GOOD-ONE')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate, hasLength(1));
      expect(plan.rowsToCreate.single.sku, 'GOOD-ONE');
      expect(plan.rowErrors, hasLength(1));
    });

    test('category and supplier names pass through untouched for the orchestrator to resolve', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row(category: 'Grains', supplier: 'ACME Distributors')],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate.single.categoryName, 'Grains');
      expect(plan.rowsToCreate.single.supplierName, 'ACME Distributors');
    });

    test('a blank category/supplier cell is null, not an empty string', () {
      final plan = engine.validate(
        headers: headers,
        rows: [row()],
        existingSkus: const {},
        existingBarcodes: const {},
      );

      expect(plan.rowsToCreate.single.categoryName, isNull);
      expect(plan.rowsToCreate.single.supplierName, isNull);
    });
  });
}
