import 'package:fulus_mobile/core/utils/csv_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = CsvParser();

  group('parse', () {
    test('splits a simple comma-separated file into rows of cells', () {
      final rows = parser.parse('name,sku,price\nRice,SKU1,1500\nBeans,SKU2,900');

      expect(rows, [
        ['name', 'sku', 'price'],
        ['Rice', 'SKU1', '1500'],
        ['Beans', 'SKU2', '900'],
      ]);
    });

    test('handles CRLF line endings the same as bare LF', () {
      final rows = parser.parse('a,b\r\n1,2\r\n3,4');
      expect(rows, [
        ['a', 'b'],
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('keeps a comma inside a quoted field as part of that one cell', () {
      final rows = parser.parse('name,note\n"Rice, 50kg bag",local staple');
      expect(rows[1], ['Rice, 50kg bag', 'local staple']);
    });

    test('unescapes a doubled quote inside a quoted field to one literal quote', () {
      final rows = parser.parse('name\n"5"" nail"');
      expect(rows[1], ['5" nail']);
    });

    test('strips a leading UTF-8 BOM so it never ends up glued to the first header', () {
      final rows = parser.parse('\uFEFFname,sku\nRice,SKU1');
      expect(rows.first.first, 'name');
    });

    test('skips a genuinely blank line rather than emitting an empty row', () {
      final rows = parser.parse('a,b\n1,2\n\n3,4');
      expect(rows, [
        ['a', 'b'],
        ['1', '2'],
        ['3', '4'],
      ]);
    });

    test('handles a file with no trailing newline on the last row', () {
      final rows = parser.parse('a,b\n1,2');
      expect(rows.last, ['1', '2']);
    });
  });

  group('parseWithHeaders', () {
    test('keys each row by its header, trimming stray whitespace', () {
      final result = parser.parseWithHeaders('name, sku ,price\nRice,SKU1,1500');

      expect(result.headers, ['name', 'sku', 'price']);
      expect(result.rows.single, {'name': 'Rice', 'sku': 'SKU1', 'price': '1500'});
    });

    test('a short row fills missing trailing columns with empty strings', () {
      final result = parser.parseWithHeaders('name,sku,barcode\nRice,SKU1');
      expect(result.rows.single['barcode'], '');
    });

    test('returns empty headers and rows for empty input', () {
      final result = parser.parseWithHeaders('');
      expect(result.headers, isEmpty);
      expect(result.rows, isEmpty);
    });
  });
}
