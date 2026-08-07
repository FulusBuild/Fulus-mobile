import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'csv_export_service.dart';
import 'pdf_export_service.dart';

enum ExportFormat { csv, pdf }

/// Stage 14 (Export half).
///
/// The single export entry point Volume 10 describes: "Exports extend
/// the same CSV/PDF mechanism... to every category" and "shares via
/// WhatsApp the same way... financial exports already do." A future
/// Reports screen (Stage 12), receipt/statement screen, or financial
/// export action (Stage 8) all call [export] with their own data —
/// this class owns turning that into a real file and handing it to
/// Android's Share Sheet (Implementation Bible: "Export uses Android
/// Share Sheet"), not deciding what belongs in any particular report.
///
/// Generation is fully offline (the data is already local — Volume 10's
/// own framing). Connectivity, if it's needed at all, is only relevant
/// to whatever the user does AFTER the Share Sheet opens (e.g. actually
/// sending via WhatsApp) — entirely outside this class's control or
/// concern, exactly like Stage 16's own "sync is optional" doesn't
/// change what this class does.
class ExportService {
  ExportService({
    CsvExportService? csvExportService,
    PdfExportService? pdfExportService,
  })  : _csv = csvExportService ?? CsvExportService(),
        _pdf = pdfExportService ?? PdfExportService();

  final CsvExportService _csv;
  final PdfExportService _pdf;

  /// [fileName] should NOT include an extension — this method appends
  /// the correct one for [format] itself, so a caller can't accidentally
  /// mismatch a `.csv` name with PDF bytes or vice versa.
  Future<void> export({
    required ExportFormat format,
    required String fileName,
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) async {
    final file = switch (format) {
      ExportFormat.csv => await _writeCsv(fileName, headers, rows),
      ExportFormat.pdf => await _writePdf(fileName, title, subtitle, headers, rows),
    };

    // share_plus's unified SharePlus.instance.share(ShareParams(...))
    // API — like every other third-party call in this stage, see
    // bluetooth_receipt_printer.dart's opening note on verifying this
    // against whatever version `flutter pub get` actually resolves.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: title),
    );
  }

  Future<File> _writeCsv(
    String fileName,
    List<String> headers,
    List<List<Object?>> rows,
  ) async {
    final content = _csv.build(headers: headers, rows: rows);
    final file = await _tempFile('$fileName.csv');
    return file.writeAsString(content);
  }

  Future<File> _writePdf(
    String fileName,
    String title,
    String? subtitle,
    List<String> headers,
    List<List<Object?>> rows,
  ) async {
    final bytes = await _pdf.build(
      title: title,
      subtitle: subtitle,
      headers: headers,
      rows: rows,
    );
    final file = await _tempFile('$fileName.pdf');
    return file.writeAsBytes(bytes);
  }

  Future<File> _tempFile(String name) async {
    // getTemporaryDirectory (path_provider, already a dependency via
    // drift_flutter) rather than an app-documents/permanent location —
    // an exported file only needs to exist long enough for the Share
    // Sheet hand-off to read it; it isn't a record this app itself needs
    // to keep or list later the way a receipt or report IS kept, as
    // actual business data, in the Drift database. Not explicitly
    // cleaned up after sharing — left to the OS's own temp-directory
    // reclamation, the same assumption path_provider's own documentation
    // makes for this directory.
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$name');
  }
}
