/// Stage 14 (Export half).
///
/// Row-building and RFC 4180 escaping are generic, uncontroversial CSV
/// mechanics. [sanitizeCell]'s formula-injection guard is NOT generic —
/// it is carried over deliberately, character-for-character, from the
/// backend's own export_service.py and verified directly against
/// backend/tests/test_export_security.py rather than re-derived from
/// general CSV-injection knowledge: a string value beginning with `=`,
/// `+`, `-`, `@`, a tab, or a carriage return gets a leading single
/// quote prefixed onto it; numbers, bools, null, and DateTime pass
/// through completely untouched. This is exactly the "Python is the
/// specification for behavior, not for code" principle (Implementation
/// Bible) applied to a security rule specifically — the WHY (Excel and
/// Sheets both execute a cell that starts with one of those characters
/// as a formula when a CSV is opened, which is how a poisoned inventory
/// or customer name field becomes code execution on whoever opens the
/// exported file) is a property of the file format those two apps
/// share, not of the backend's Python runtime, so the same guard is
/// exactly as necessary here.
import 'export_metadata.dart';

class CsvExportService {
  static const _dangerousPrefixes = ['=', '+', '-', '@', '\t', '\r'];

  /// Builds a complete CSV document (header row + data rows) as a single
  /// string, CRLF-terminated per RFC 4180 (the format's own specified
  /// line ending, not merely this platform's convention). When
  /// [metadata] is given, it's written as plain key/value rows above
  /// the real header row, then a blank row — every spreadsheet app
  /// that opens this file still just sees ordinary rows, no special
  /// CSV feature required, and nothing here changes [rows]' own column
  /// count or content.
  String build({
    ExportMetadata? metadata,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final buffer = StringBuffer();
    if (metadata != null) {
      buffer.write(_buildRow(['Business', metadata.businessName]));
      buffer.write(_buildRow(['Report', metadata.reportName]));
      buffer.write(_buildRow(['Period', metadata.dateRangeLabel]));
      buffer.write(_buildRow(['Generated', metadata.generatedAt.toIso8601String()]));
      buffer.write(_buildRow(['Currency', metadata.currencySymbol]));
      for (final filter in metadata.appliedFilters) {
        buffer.write(_buildRow(['Filter', filter]));
      }
      buffer.write(_buildRow(const []));
    }
    buffer.write(_buildRow(headers.cast<Object?>()));
    for (final row in rows) {
      buffer.write(_buildRow(row));
    }
    return buffer.toString();
  }

  String _buildRow(List<Object?> cells) {
    final escaped = cells.map((cell) => _escapeField(sanitizeCell(cell)));
    return '${escaped.join(',')}\r\n';
  }

  /// Public specifically so pdf_export_service.dart can apply the exact
  /// same guard to table cells rendered into a PDF — Volume 10 doesn't
  /// distinguish "safe" and "unsafe" export formats, and a PDF built
  /// from the same underlying row data deserves the same treatment, even
  /// though a PDF viewer doesn't execute formulas the way a spreadsheet
  /// does; consistency between the two formats matters more here than
  /// the (much smaller) actual risk on the PDF side.
  static Object? sanitizeCell(Object? value) {
    if (value is! String) return value;
    if (value.isEmpty) return value;
    final firstChar = value[0];
    if (_dangerousPrefixes.contains(firstChar)) {
      return "'$value";
    }
    return value;
  }

  String _escapeField(Object? value) {
    final text = _cellToString(value);
    final needsQuoting =
        text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
    if (!needsQuoting) return text;
    return '"${text.replaceAll('"', '""')}"';
  }

  String _cellToString(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }
}
