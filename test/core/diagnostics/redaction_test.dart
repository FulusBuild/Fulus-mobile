import 'package:fulus_mobile/core/diagnostics/models/breadcrumb.dart';
import 'package:fulus_mobile/core/diagnostics/models/device_context.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_enums.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_event.dart';
import 'package:fulus_mobile/core/diagnostics/redaction/diagnostic_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const redactor = DiagnosticRedactor();

  group('redactValue', () {
    test('replaces the whole value when the key name is sensitive', () {
      expect(redactor.redactValue('password', 'hunter2'), '[REDACTED]');
      expect(redactor.redactValue('authToken', 'abc123'), '[REDACTED]');
      expect(redactor.redactValue('refreshToken', 'abc123'), '[REDACTED]');
      expect(redactor.redactValue('pin', '1234'), '[REDACTED]');
      expect(redactor.redactValue('Authorization', 'Bearer xyz'), '[REDACTED]');
      expect(redactor.redactValue('clientSecret', 'xyz'), '[REDACTED]');
    });

    test('key matching is case-insensitive and works on camelCase/snake_case', () {
      expect(redactor.redactValue('PASSWORD', 'x'), '[REDACTED]');
      expect(redactor.redactValue('api_key', 'x'), '[REDACTED]');
      expect(redactor.redactValue('ApiKey', 'x'), '[REDACTED]');
    });

    test('does not false-positive on "pin" as a substring of another word', () {
      // "pin" is deliberately word-boundary matched — "shipping" and
      // "opinion" must not be treated as sensitive.
      expect(redactor.redactValue('shippingMethod', 'courier'), 'courier');
      expect(redactor.redactValue('opinionScore', '5'), '5');
    });

    test('leaves an ordinary business value untouched', () {
      expect(redactor.redactValue('Product ID', '01ARZ3NDEKTSV4RRFFQ69G5FAV'), '01ARZ3NDEKTSV4RRFFQ69G5FAV');
      expect(redactor.redactValue('Sale ID', '01ARZ3NDEKTSV4RRFFQ69G5FAV'), '01ARZ3NDEKTSV4RRFFQ69G5FAV');
    });
  });

  group('redactText', () {
    test('redacts a JWT-shaped substring embedded in free text', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpM';
      final result = redactor.redactText('Auth failed with token $jwt attached');
      expect(result.contains(jwt), isFalse);
      expect(result.contains('[REDACTED]'), isTrue);
    });

    test('redacts a "Bearer <token>" pattern', () {
      final result = redactor.redactText('Authorization: Bearer abcdef1234567890xyz');
      expect(result.contains('abcdef1234567890xyz'), isFalse);
    });

    test('does not touch a ULID-shaped ID, which contains no dots', () {
      const ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
      expect(redactor.redactText('Product $ulid failed to save'), contains(ulid));
    });

    test('leaves ordinary exception text completely unchanged', () {
      const message = 'FOREIGN KEY constraint failed';
      expect(redactor.redactText(message), message);
    });
  });

  group('redactMap', () {
    test('redacts sensitive keys and leaves others untouched', () {
      final result = redactor.redactMap({
        'password': 'hunter2',
        'Product ID': 'abc',
      });
      expect(result['password'], '[REDACTED]');
      expect(result['Product ID'], 'abc');
    });
  });

  group('redactEvidence', () {
    test('redacts EvidenceItem values by label', () {
      final result = redactor.redactEvidence([
        const EvidenceItem('Access token', 'secret-value'),
        const EvidenceItem('Product ID', '184'),
      ]);
      expect(result[0].value, '[REDACTED]');
      expect(result[1].value, '184');
    });
  });

  group('redactEvent', () {
    test('redacts title, message, stack trace, evidence, and breadcrumbs together', () {
      final event = DiagnosticEvent(
        id: 'evt-1',
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.authentication,
        title: 'Sign-in failed',
        message: 'token=Bearer abcdef1234567890xyz was rejected',
        cause: const DiagnosticCause(description: 'ok', confidence: DiagnosticConfidence.high),
        evidence: const [EvidenceItem('password', 'hunter2')],
        breadcrumbs: [
          Breadcrumb(message: 'used token abcdef1234567890xyz', timestamp: DateTime(2026, 1, 1)),
        ],
        device: const DeviceContext.unknown(),
      );

      final redacted = redactor.redactEvent(event);

      expect(redacted.message.contains('abcdef1234567890xyz'), isFalse);
      expect(redacted.evidence.single.value, '[REDACTED]');
      expect(redacted.breadcrumbs.single.message.contains('abcdef1234567890xyz'), isFalse);
      // Non-sensitive fields pass through unchanged.
      expect(redacted.id, event.id);
      expect(redacted.severity, event.severity);
    });
  });
}
