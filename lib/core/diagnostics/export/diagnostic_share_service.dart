import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/diagnostic_event.dart';
import 'diagnostic_report_generator.dart';

enum DiagnosticReportFormat { text, json }

/// Shares diagnostic reports through the platform Share Sheet — brief
/// Section 11's "This error / Today's logs / Last 7 days / Full
/// diagnostic report", all four backed by this one class, differing
/// only in which events the caller already fetched
/// (DiagnosticLogger.getForExport with an appropriate DiagnosticFilter)
/// before calling in here.
///
/// Follows the exact temp-file-then-`Share.shareXFiles` pattern
/// core/export/export_service.dart already uses for CSV/PDF exports —
/// verified directly against that file rather than assumed, since
/// `share_plus`'s API has changed across major versions (see
/// pubspec.yaml's own merge note on this package) and matching a
/// call site already proven to work in this exact app removes any
/// doubt about which API shape is current here.
class DiagnosticShareService {
  DiagnosticShareService({DiagnosticReportGenerator? reportGenerator})
      : _reportGenerator = reportGenerator ?? const DiagnosticReportGenerator();

  final DiagnosticReportGenerator _reportGenerator;

  Future<void> shareEvent(DiagnosticEvent event) => _share(
        events: [event],
        reportTitle: event.title,
        filenamePrefix: 'fulus-error',
      );

  Future<void> shareRange({
    required List<DiagnosticEvent> events,
    required String rangeLabel,
    DiagnosticReportFormat format = DiagnosticReportFormat.text,
  }) =>
      _share(
        events: events,
        reportTitle: 'Fulus Diagnostic Report — $rangeLabel',
        filenamePrefix: 'fulus-diagnostics',
        format: format,
      );

  Future<void> _share({
    required List<DiagnosticEvent> events,
    required String reportTitle,
    required String filenamePrefix,
    DiagnosticReportFormat format = DiagnosticReportFormat.text,
  }) async {
    final isJson = format == DiagnosticReportFormat.json;
    final content = isJson
        ? _reportGenerator.generateJsonReport(events, reportTitle: reportTitle)
        : _reportGenerator.generateTextReport(events, reportTitle: reportTitle);

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = isJson ? 'json' : 'txt';
    final file = File('${dir.path}/$filenamePrefix-$timestamp.$extension');
    await file.writeAsString(content);

    await Share.shareXFiles([XFile(file.path)], subject: reportTitle);
  }
}
