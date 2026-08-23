import 'dart:convert';

import '../models/diagnostic_event.dart';
import '../redaction/diagnostic_redactor.dart';

/// Turns a list of [DiagnosticEvent]s into a shareable report — plain
/// text (readable dropped straight into WhatsApp/Telegram/email) or
/// JSON (structured, for a developer who wants to parse it). Used for
/// every share option the brief's own Section 11 lists ("This error",
/// "Today's logs", "Last 7 days", "Full diagnostic report") — they
/// differ only in which events the caller fetched beforehand
/// (DiagnosticShareService's job), not in how the report itself is
/// built.
///
/// Redacts again here, defensively, even though every event was already
/// redacted once at capture time (DiagnosticLogger.captureError calls
/// DiagnosticRedactor.redactEvent before anything is persisted) — see
/// DiagnosticRedactor's own header comment: export is the actual point
/// data leaves the device, so it gets its own independent pass rather
/// than trusting an invariant established elsewhere to have held.
class DiagnosticReportGenerator {
  const DiagnosticReportGenerator({DiagnosticRedactor? redactor})
      : _redactor = redactor ?? const DiagnosticRedactor();

  final DiagnosticRedactor _redactor;

  String generateTextReport(List<DiagnosticEvent> events, {String reportTitle = 'Fulus Diagnostic Report'}) {
    final redacted = events.map(_redactor.redactEvent).toList();
    final buffer = StringBuffer();
    buffer.writeln('=' * 48);
    buffer.writeln(reportTitle);
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Events included: ${redacted.length}');
    if (redacted.isNotEmpty) {
      final device = redacted.first.device;
      buffer.writeln('App version: ${device.appVersion} (build ${device.buildNumber})');
      buffer.writeln('Device: ${device.deviceModel}');
      buffer.writeln('OS: ${device.osVersion}');
    }
    buffer.writeln('=' * 48);
    buffer.writeln();

    if (redacted.isEmpty) {
      buffer.writeln('No diagnostic events in the selected range.');
      return buffer.toString();
    }

    for (var i = 0; i < redacted.length; i++) {
      _writeEvent(buffer, redacted[i], index: i + 1, total: redacted.length);
    }
    return buffer.toString();
  }

  void _writeEvent(StringBuffer buffer, DiagnosticEvent event, {required int index, required int total}) {
    buffer.writeln('-' * 48);
    buffer.writeln('[$index/$total] ${event.severity.label.toUpperCase()} — ${event.title}');
    buffer.writeln(event.timestamp.toIso8601String());
    if (event.occurrenceCount > 1) {
      buffer.writeln(
          'Occurred ${event.occurrenceCount} times (first: ${event.firstOccurredAt.toIso8601String()})');
    }
    buffer.writeln();
    buffer.writeln(event.message);
    buffer.writeln();

    buffer.writeln('Likely cause: ${event.cause.description}');
    buffer.writeln('Confidence: ${event.cause.confidence.label}');
    buffer.writeln();

    buffer.writeln('Where: ${event.screen ?? '(no screen)'} -> ${event.component ?? '(no component)'}'
        '${event.operation != null ? ' -> ${event.operation}' : ''}');
    if (event.failureStage != null) {
      buffer.writeln('Failure stage: ${event.failureStage}');
    }
    buffer.writeln();

    if (event.evidence.isNotEmpty) {
      buffer.writeln('Evidence:');
      for (final item in event.evidence) {
        buffer.writeln('  • ${item.label}: ${item.value}');
      }
      buffer.writeln();
    }

    if (event.technicalContext.isNotEmpty) {
      buffer.writeln('Technical context:');
      for (final item in event.technicalContext) {
        buffer.writeln('  • ${item.label}: ${item.value}');
      }
      buffer.writeln();
    }

    if (event.breadcrumbs.isNotEmpty) {
      buffer.writeln('Recent activity:');
      for (final crumb in event.breadcrumbs) {
        final time = crumb.timestamp.toIso8601String().substring(11, 19);
        buffer.writeln('  $time  ${crumb.message}');
      }
      buffer.writeln();
    }

    buffer.writeln('Technical details:');
    buffer.writeln('  Exception type: ${event.exceptionType ?? 'unknown'}');
    if (event.errorCode != null) {
      buffer.writeln('  Error code: ${event.errorCode}');
    }
    if (event.stackTrace != null && event.stackTrace!.isNotEmpty) {
      buffer.writeln('  Stack trace:');
      for (final line in event.stackTrace!.split('\n')) {
        buffer.writeln('    $line');
      }
    }
    buffer.writeln();
  }

  String generateJsonReport(List<DiagnosticEvent> events, {String reportTitle = 'Fulus Diagnostic Report'}) {
    final redacted = events.map(_redactor.redactEvent).toList();
    final payload = {
      'report': reportTitle,
      'generatedAt': DateTime.now().toIso8601String(),
      'eventCount': redacted.length,
      'events': redacted.map((e) => e.toJson()).toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }
}
