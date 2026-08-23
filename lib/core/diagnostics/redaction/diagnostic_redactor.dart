import '../models/breadcrumb.dart';
import '../models/diagnostic_event.dart';

/// Strips secrets before anything reaches storage, the report generator,
/// or the Share Sheet — applied at capture time (diagnostic_logger.dart
/// calls this on every breadcrumb/evidence/context map it's handed) AND
/// again, defensively, at export time (export/diagnostic_report_generator.dart),
/// since export is the actual point data leaves the device.
///
/// Two independent passes, both conservative by design:
///
/// 1. **Key-name matching** — a field literally named `password`,
///    `token`, `pin`, etc. has its value replaced outright, regardless
///    of what the value looks like. This is the primary, precise
///    mechanism.
/// 2. **Value-shape matching** — a small set of value patterns
///    distinctive enough that legitimate diagnostic evidence in this
///    app's schema could never produce them by coincidence (a JWT's
///    three dot-separated segments, a `Bearer ...` header). Deliberately
///    does NOT try to redact "any long random-looking string" — this
///    app's own local IDs (Sale/Product/Customer `localId`, all ULIDs —
///    see pubspec.yaml's own comment on why ULID was chosen) are
///    exactly that shape and are legitimate, useful evidence
///    ("Product ID: 01ARZ3ND..."); a shape-only rule broad enough to
///    catch real secrets would also silently strip the IDs a developer
///    most needs to see. Precision here matters as much as coverage.
class DiagnosticRedactor {
  const DiagnosticRedactor();

  static const _sensitiveKeyPattern = r'password|passwd|pwd|token|secret|'
      r'credential|api[_-]?key|access[_-]?token|refresh[_-]?token|'
      r'authorization|bearer|\bpin\b|private[_-]?key|client[_-]?secret';

  static final RegExp _sensitiveKeyRegExp =
      RegExp(_sensitiveKeyPattern, caseSensitive: false);

  // Three dot-separated base64url segments — a JWT's own shape, and not
  // one this app's ULID-based IDs (which never contain a period) can
  // produce by coincidence.
  static final RegExp _jwtPattern =
      RegExp(r'[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}');

  // Case-insensitive: a raw header line or a value someone concatenated
  // "Bearer <token>" into.
  static final RegExp _bearerPattern =
      RegExp(r'Bearer\s+[A-Za-z0-9._-]{10,}', caseSensitive: false);

  static const _redactedValue = '[REDACTED]';

  bool _isSensitiveKey(String key) => _sensitiveKeyRegExp.hasMatch(key);

  /// Redacts secret-shaped substrings inside free text (an exception
  /// message, a stack trace) without touching the rest of the string —
  /// unlike [redactValue], which replaces a whole value once its *key*
  /// is known to be sensitive.
  String redactText(String input) {
    var result = input.replaceAll(_bearerPattern, 'Bearer $_redactedValue');
    result = result.replaceAllMapped(_jwtPattern, (_) => _redactedValue);
    return result;
  }

  /// Redacts a single value given its key/label — replaces the value
  /// entirely if the key itself is sensitive, otherwise scans the value
  /// text for embedded secret shapes.
  String redactValue(String key, String value) {
    if (_isSensitiveKey(key)) return _redactedValue;
    return redactText(value);
  }

  Map<String, String> redactMap(Map<String, String> input) {
    if (input.isEmpty) return input;
    return {for (final entry in input.entries) entry.key: redactValue(entry.key, entry.value)};
  }

  List<EvidenceItem> redactEvidence(List<EvidenceItem> items) {
    if (items.isEmpty) return items;
    return items.map((item) => EvidenceItem(item.label, redactValue(item.label, item.value))).toList();
  }

  /// Stack traces are frame lists (file/line/function) and don't
  /// normally carry secrets, but this runs the same text pass anyway —
  /// cheap insurance against a value that got interpolated into an
  /// exception's own message, which frequently shows up as the first
  /// line of a printed stack trace.
  String? redactStackTrace(String? stackTrace) =>
      stackTrace == null ? null : redactText(stackTrace);

  /// Applies every pass above to a whole [DiagnosticEvent] at once —
  /// the one call site diagnostic_logger.dart and the report generator
  /// both actually use, so redaction can never be accidentally skipped
  /// for one field while applied to another.
  DiagnosticEvent redactEvent(DiagnosticEvent event) {
    return DiagnosticEvent(
      id: event.id,
      severity: event.severity,
      category: event.category,
      title: redactText(event.title),
      message: redactText(event.message),
      timestamp: event.timestamp,
      firstOccurredAt: event.firstOccurredAt,
      occurrenceCount: event.occurrenceCount,
      component: event.component,
      operation: event.operation,
      screen: event.screen,
      exceptionType: event.exceptionType,
      errorCode: event.errorCode,
      stackTrace: redactStackTrace(event.stackTrace),
      cause: DiagnosticCause(
        description: redactText(event.cause.description),
        confidence: event.cause.confidence,
      ),
      evidence: redactEvidence(event.evidence),
      technicalContext: redactEvidence(event.technicalContext),
      breadcrumbs: event.breadcrumbs
          .map((b) => Breadcrumb(
                message: redactText(b.message),
                timestamp: b.timestamp,
                category: b.category,
                data: redactMap(b.data),
              ))
          .toList(),
      failureStage: event.failureStage,
      device: event.device,
      lifecycleStatus: event.lifecycleStatus,
    );
  }
}
