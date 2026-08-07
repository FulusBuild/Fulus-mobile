import 'package:fulus_mobile/core/export/csv_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors backend/tests/test_export_security.py directly — the same
/// dangerous-prefix set, the same "numbers pass through untouched"
/// assertion, the same "only the FIRST character matters" case. See
/// csv_export_service.dart's own doc comment on why this rule is
/// carried over character-for-character rather than re-derived.
void main() {
  final service = CsvExportService();

  group('CsvExportService.sanitizeCell — formula injection guard', () {
    for (final prefix in ['=', '+', '-', '@', '\t', '\r']) {
      test('prefixes a string starting with "$prefix" with a single quote', () {
        final input = '${prefix}cmd|calc.exe';
        final result = CsvExportService.sanitizeCell(input);
        expect(result, "'$input");
      });
    }

    test('a safe string is returned completely unchanged', () {
      expect(CsvExportService.sanitizeCell('Rice 50kg'), 'Rice 50kg');
    });

    test('an int passes through untouched, never stringified or prefixed', () {
      expect(CsvExportService.sanitizeCell(1500), 1500);
    });

    test('a double passes through untouched', () {
      expect(CsvExportService.sanitizeCell(99.99), 99.99);
    });

    test('null passes through untouched', () {
      expect(CsvExportService.sanitizeCell(null), null);
    });

    test('a bool passes through untouched', () {
      expect(CsvExportService.sanitizeCell(true), true);
    });

    test('empty string is returned unchanged, not indexed into', () {
      expect(CsvExportService.sanitizeCell(''), '');
    });

    test('only the first character is dangerous — a mid-string "=" is safe', () {
      expect(CsvExportService.sanitizeCell('A=B'), 'A=B');
    });
  });

  group('CsvExportService.build — RFC 4180 escaping', () {
    test('wraps a field containing a comma in double quotes', () {
      final csv = service.build(
        headers: ['Name', 'Notes'],
        rows: [
          ['Rice', 'bag, torn'],
        ],
      );
      expect(csv, contains('"bag, torn"'));
    });

    test('doubles an embedded double-quote', () {
      final csv = service.build(
        headers: ['Name'],
        rows: [
          ['5" nails'],
        ],
      );
      expect(csv, contains('"5"" nails"'));
    });

    test('formats a DateTime cell as ISO 8601', () {
      final date = DateTime.utc(2026, 7, 30);
      final csv = service.build(headers: ['Date'], rows: [
        [date],
      ]);
      expect(csv, contains(date.toIso8601String()));
    });

    test('a null cell renders as an empty field, not the string "null"', () {
      final csv = service.build(headers: ['Notes'], rows: [
        [null],
      ]);
      expect(csv, isNot(contains('null')));
    });

    test('rows are CRLF-terminated per RFC 4180', () {
      final csv = service.build(headers: ['A'], rows: [
        ['1'],
      ]);
      expect(csv, endsWith('\r\n'));
    });

    test('a malicious product name is neutralized in real output', () {
      final csv = service.build(
        headers: ['Product'],
        rows: [
          ['=HYPERLINK("http://evil.example","click")'],
        ],
      );
      expect(csv, contains("'=HYPERLINK"));
    });
  });
}
