import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'csv_export_service.dart';

/// Stage 14 (Export half).
///
/// Dart PDF generation, per the Implementation Bible's explicit "Use
/// Dart PDF library" instruction — never ReportLab, never routed through
/// the Python backend (Architecture's own "everything communicates
/// directly with Flutter, never through Python," restated for this
/// stage specifically). Deliberately minimal — a title, an optional
/// subtitle (a date range, a location name — whatever the caller's
/// report needs), and a table. This is a shared rendering primitive for
/// Volume 10's five report categories and Volume 8/10's financial
/// exports to all extend, not a bespoke layout per report type; per-report
/// column choices belong with whichever stage owns that report's data
/// (Stage 8 Finance, Stage 12 Reports), not fabricated here against
/// data this stage has no real report to test against.
///
/// **Built without network/compiler access** — see
/// bluetooth_receipt_printer.dart's own note on this pass's constraint;
/// the pdf package's exact current widget API should be checked against
/// whatever version resolves. This file deliberately sticks to pdf's
/// most fundamental building blocks (pw.Table, pw.TableRow, pw.Text)
/// rather than higher-level convenience helpers specifically because
/// those fundamentals are far less likely to have changed shape across
/// recent package versions than a helper method might have.
import 'csv_export_service.dart';
import 'export_metadata.dart';

class PdfExportService {
  Future<Uint8List> build({
    ExportMetadata? metadata,
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if (subtitle != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11)),
          ],
          if (metadata != null) ...[
            pw.SizedBox(height: 8),
            _buildMetadataBlock(metadata),
          ],
          pw.SizedBox(height: 16),
          _buildTable(headers, rows),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildMetadataBlock(ExportMetadata metadata) {
    final lines = [
      'Business: ${metadata.businessName}',
      'Period: ${metadata.dateRangeLabel}',
      'Generated: ${metadata.generatedAt.toIso8601String()}',
      'Currency: ${metadata.currencySymbol}',
      if (metadata.appliedFilters.isNotEmpty) 'Filters: ${metadata.appliedFilters.join(', ')}',
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    );
  }

  pw.Widget _buildTable(List<String> headers, List<List<Object?>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                  ),
                ),
              )
              .toList(),
        ),
        for (final row in rows)
          pw.TableRow(
            children: row
                .map(
                  (cell) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    // Same formula-injection guard as the CSV path — see
                    // CsvExportService.sanitizeCell's own doc comment on
                    // why a PDF gets the identical treatment despite the
                    // much smaller actual risk on this side.
                    child: pw.Text(
                      _cellToString(CsvExportService.sanitizeCell(cell)),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  String _cellToString(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }
}
