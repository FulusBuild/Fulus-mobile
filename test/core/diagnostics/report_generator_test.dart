import 'dart:convert';

import 'package:fulus_mobile/core/diagnostics/export/diagnostic_report_generator.dart';
import 'package:fulus_mobile/core/diagnostics/models/breadcrumb.dart';
import 'package:fulus_mobile/core/diagnostics/models/device_context.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_event.dart';
import 'package:flutter_test/flutter_test.dart';

DiagnosticEvent _event({String id = 'evt-1', String? stackTrace}) {
  return DiagnosticEvent(
    id: id,
    severity: DiagnosticSeverity.error,
    category: DiagnosticCategory.sales,
    title: 'Sale failed',
    message: 'The sale could not be completed.',
    component: 'DraftCartRepositoryImpl',
    operation: 'completeSale',
    screen: 'SellScreen',
    exceptionType: 'SqliteException',
    stackTrace: stackTrace,
    cause: const DiagnosticCause(
      description: 'A record this operation referenced no longer exists.',
      confidence: DiagnosticConfidence.high,
    ),
    evidence: const [
      EvidenceItem('Product ID', '01ARZ3NDEKTSV4RRFFQ69G5FAV'),
      EvidenceItem('password', 'shouldNeverAppearEvenHere'),
    ],
    breadcrumbs: [
      Breadcrumb(message: 'Sale transaction started', timestamp: DateTime(2026, 1, 1, 9, 0)),
      Breadcrumb(message: 'Inventory update started', timestamp: DateTime(2026, 1, 1, 9, 0, 1)),
    ],
    device: const DeviceContext(
      appVersion: '1.1.6',
      buildNumber: '42',
      deviceModel: 'Test Device',
      osName: 'Android',
      osVersion: 'Android 14',
    ),
  );
}

void main() {
  const generator = DiagnosticReportGenerator();

  group('generateTextReport', () {
    test('includes device info, event count, and title', () {
      final report = generator.generateTextReport([_event()], reportTitle: 'Test Report');
      expect(report, contains('Test Report'));
      expect(report, contains('Events included: 1'));
      expect(report, contains('1.1.6'));
      expect(report, contains('Test Device'));
    });

    test('includes the plain-language cause and confidence, not just the '
        'raw exception', () {
      final report = generator.generateTextReport([_event()]);
      expect(report, contains('A record this operation referenced no longer exists.'));
      expect(report, contains('HIGH'));
    });

    test('includes evidence, breadcrumbs, and where/component/operation', () {
      final report = generator.generateTextReport([_event()]);
      expect(report, contains('Product ID: 01ARZ3NDEKTSV4RRFFQ69G5FAV'));
      expect(report, contains('Sale transaction started'));
      expect(report, contains('DraftCartRepositoryImpl'));
      expect(report, contains('completeSale'));
    });

    test('redacts sensitive evidence even though the event was already '
        'redacted once at capture time — defense in depth', () {
      final report = generator.generateTextReport([_event()]);
      expect(report.contains('shouldNeverAppearEvenHere'), isFalse);
      expect(report, contains('[REDACTED]'));
    });

    test('handles an empty event list gracefully', () {
      final report = generator.generateTextReport(const []);
      expect(report, contains('No diagnostic events'));
    });

    test('numbers multiple events and separates them', () {
      final report = generator.generateTextReport([_event(id: 'a'), _event(id: 'b')]);
      expect(report, contains('[1/2]'));
      expect(report, contains('[2/2]'));
    });

    test('omits a null stack trace section rather than printing "null"', () {
      final report = generator.generateTextReport([_event(stackTrace: null)]);
      expect(report.contains('null'), isFalse);
    });

    test('includes a truncated stack trace when present', () {
      final report = generator.generateTextReport([_event(stackTrace: '#0 someFunction (file.dart:10)')]);
      expect(report, contains('#0 someFunction'));
    });
  });

  group('generateJsonReport', () {
    test('produces valid, parseable JSON with the expected top-level shape', () {
      final report = generator.generateJsonReport([_event()], reportTitle: 'JSON Test');
      final decoded = jsonDecode(report) as Map<String, Object?>;
      expect(decoded['report'], 'JSON Test');
      expect(decoded['eventCount'], 1);
      expect(decoded['events'], isA<List>());
    });

    test('redacts sensitive evidence in the JSON output too', () {
      final report = generator.generateJsonReport([_event()]);
      expect(report.contains('shouldNeverAppearEvenHere'), isFalse);
    });

    test('round-trips event fields correctly', () {
      final report = generator.generateJsonReport([_event()]);
      final decoded = jsonDecode(report) as Map<String, Object?>;
      final events = decoded['events'] as List;
      final event = events.single as Map<String, Object?>;
      expect(event['title'], 'Sale failed');
      expect(event['severity'], 'error');
    });
  });
}
