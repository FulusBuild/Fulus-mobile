import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fulus_mobile/core/diagnostics/engine/diagnostic_signal.dart';
import 'package:fulus_mobile/core/diagnostics/engine/root_cause_engine.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_enums.dart';
import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';

DiagnosticSignal _signal(
  Object error, {
  DiagnosticCategory categoryHint = DiagnosticCategory.unknown,
  String? component,
  String? operation,
  Map<String, String>? context,
  bool? isOffline,
}) {
  return DiagnosticSignal(
    error: error,
    stackTrace: StackTrace.current,
    categoryHint: categoryHint,
    component: component,
    operation: operation,
    context: context,
    isOffline: isOffline,
  );
}

void main() {
  const engine = RootCauseEngine();

  group('unknown fallback', () {
    test('an exception matching nothing returns DiagnosticCause.unknown with '
        'UNKNOWN confidence', () {
      final result = engine.classify(_signal(Exception('some never-before-seen error')));
      expect(result.cause.confidence, DiagnosticConfidence.unknown);
      expect(result.matchedRuleName, isNull);
    });

    test('never invents a cause for an exotic error shape', () {
      final result = engine.classify(_signal(Object()));
      expect(result.cause.confidence, DiagnosticConfidence.unknown);
    });
  });

  group('database rules', () {
    test('foreign key violation — HIGH confidence, correct evidence', () {
      final result = engine.classify(
        _signal(Exception('FOREIGN KEY constraint failed')),
      );
      expect(result.matchedRuleName, 'database.foreignKeyViolation');
      expect(result.cause.confidence, DiagnosticConfidence.high);
      expect(result.evidence.any((e) => e.value == 'FOREIGN KEY'), isTrue);
    });

    test('unique constraint violation', () {
      final result = engine.classify(_signal(Exception('UNIQUE constraint failed: products.sku')));
      expect(result.matchedRuleName, 'database.uniqueConstraintViolation');
    });

    test('not null constraint violation', () {
      final result = engine.classify(_signal(Exception('NOT NULL constraint failed: sales.total')));
      expect(result.matchedRuleName, 'database.notNullConstraint');
    });

    test('database locked — MEDIUM confidence', () {
      final result = engine.classify(_signal(Exception('database is locked')));
      expect(result.matchedRuleName, 'database.locked');
      expect(result.cause.confidence, DiagnosticConfidence.medium);
    });

    test('disk full', () {
      final result = engine.classify(_signal(Exception('database or disk is full')));
      expect(result.matchedRuleName, 'database.diskFull');
    });

    test('an otherwise-unrecognized SqliteException still lands in the '
        'database category at LOW confidence, not UNKNOWN', () {
      final result = engine.classify(_signal(Exception('SqliteException: some new error shape')));
      expect(result.matchedRuleName, 'database.generic');
      expect(result.cause.confidence, DiagnosticConfidence.low);
    });
  });

  group('network rules', () {
    final requestOptions = RequestOptions(path: '/sync/sales');

    test('connection error while offline — HIGH confidence', () {
      final error = DioException(requestOptions: requestOptions, type: DioExceptionType.connectionError);
      final result = engine.classify(_signal(error, isOffline: true));
      expect(result.matchedRuleName, 'network.offlineBeforeResponse');
      expect(result.cause.confidence, DiagnosticConfidence.high);
    });

    test('connectionError type alone (isOffline unset) still matches offline rule', () {
      final error = DioException(requestOptions: requestOptions, type: DioExceptionType.connectionError);
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'network.offlineBeforeResponse');
    });

    test('receive timeout — MEDIUM confidence', () {
      final error = DioException(requestOptions: requestOptions, type: DioExceptionType.receiveTimeout);
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'network.serverTimeout');
      expect(result.cause.confidence, DiagnosticConfidence.medium);
    });

    test('HTTP 500 response — server error rule, includes status in evidence', () {
      final response = Response(requestOptions: requestOptions, statusCode: 500);
      final error = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: response,
      );
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'network.serverError');
      expect(result.evidence.any((e) => e.value == '500'), isTrue);
    });
  });

  group('auth rules', () {
    test('local session expired — matched via AuthFailure.message, HIGH confidence', () {
      final result = engine.classify(_signal(const AuthFailure.sessionExpired()));
      expect(result.matchedRuleName, 'auth.localSessionInvalid');
      expect(result.cause.confidence, DiagnosticConfidence.high);
    });

    test('account deactivated', () {
      final result = engine.classify(_signal(const AuthFailure.accountDeactivated()));
      expect(result.matchedRuleName, 'auth.accountDeactivated');
    });

    test('account locked', () {
      final result = engine.classify(
        _signal(AuthFailure.accountLocked(lockedUntil: DateTime.now().add(const Duration(minutes: 15)))),
      );
      expect(result.matchedRuleName, 'auth.accountLocked');
    });

    test('forbidden', () {
      final result = engine.classify(_signal(const AuthFailure.forbidden()));
      expect(result.matchedRuleName, 'auth.forbidden');
    });

    test('sync-layer HTTP 401 is distinguished from a local session failure', () {
      final requestOptions = RequestOptions(path: '/sync/sales');
      final response = Response(requestOptions: requestOptions, statusCode: 401);
      final error = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: response,
      );
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'auth.syncRejected');
    });
  });

  group('sync rules', () {
    test('[CONFLICT] prefix (from ConflictResolver.annotate) is recognized', () {
      final result = engine.classify(
        _signal(Exception('[CONFLICT] Server rejected: version mismatch')),
      );
      expect(result.matchedRuleName, 'sync.versionConflict');
      expect(result.cause.confidence, DiagnosticConfidence.high);
    });

    test('missing sync handler', () {
      final result = engine.classify(
        _signal(StateError('No sync handler registered for entityType "widget".')),
      );
      expect(result.matchedRuleName, 'sync.handlerMissing');
    });

    test('attentionNeeded threshold with no more specific match', () {
      final result = engine.classify(
        _signal(Exception('connection reset'), context: {'syncOutcome': 'attentionNeeded'}),
      );
      expect(result.matchedRuleName, 'sync.attentionThreshold');
      expect(result.cause.confidence, DiagnosticConfidence.medium);
    });
  });

  group('file system rules', () {
    test('directory unavailable — permission denied', () {
      final error = FileSystemException(
        'Cannot open file',
        '/storage/emulated/0/receipts/x.pdf',
        const OSError('Permission denied', 13),
      );
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'fileSystem.directoryUnavailable');
      expect(result.evidence.any((e) => e.label == 'Path'), isTrue);
    });

    test('disk full via file system error', () {
      final error = FileSystemException(
        'Cannot write file',
        '/storage/emulated/0/backups/x.zip',
        const OSError('No space left on device', 28),
      );
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'fileSystem.diskFull');
    });

    test('an unrecognized FileSystemException still lands as fileSystem.generic, '
        'not UNKNOWN', () {
      final error = FileSystemException('Something else', '/tmp/x');
      final result = engine.classify(_signal(error));
      expect(result.matchedRuleName, 'fileSystem.generic');
      expect(result.cause.confidence, DiagnosticConfidence.low);
    });
  });

  group('validation / business-rule rules — severity override', () {
    test('ValidationFailure is classified with HIGH confidence and its '
        'fieldErrors become evidence', () {
      final result = engine.classify(
        _signal(const ValidationFailure(fieldErrors: {'quantity': 'Must be greater than 0'})),
      );
      expect(result.matchedRuleName, 'validation.fieldRejection');
      expect(result.evidence.any((e) => e.label == 'quantity'), isTrue);
      expect(result.severityOverride, DiagnosticSeverity.warning);
    });

    test('BusinessRuleFailure is downgraded to warning severity', () {
      final result = engine.classify(_signal(const BusinessRuleFailure('Insufficient stock.')));
      expect(result.matchedRuleName, 'validation.businessRuleRejection');
      expect(result.severityOverride, DiagnosticSeverity.warning);
    });
  });

  group('missing entity rule', () {
    test("this app's own cart guard clause is recognized", () {
      final result = engine.classify(_signal(StateError('That product is no longer available.')));
      expect(result.matchedRuleName, 'state.missingEntity');
      expect(result.cause.confidence, DiagnosticConfidence.medium);
    });

    test('an unrelated StateError does not match', () {
      final result = engine.classify(_signal(StateError('A sale must have at least one item.')));
      expect(result.matchedRuleName, isNot('state.missingEntity'));
    });
  });

  group('startup fallback — checked last, not before category-specific rules', () {
    test('a plain unrecognized error hinted as startup uses the startup rule', () {
      final result = engine.classify(
        _signal(Exception('something failed during init'), categoryHint: DiagnosticCategory.startup),
      );
      expect(result.matchedRuleName, 'startup.generic');
      expect(result.cause.confidence, DiagnosticConfidence.medium);
    });

    test('a database failure during startup is still diagnosed as a database '
        'failure, not shadowed by the startup fallback', () {
      final result = engine.classify(
        _signal(
          Exception('FOREIGN KEY constraint failed'),
          categoryHint: DiagnosticCategory.startup,
        ),
      );
      expect(result.matchedRuleName, 'database.foreignKeyViolation');
    });
  });

  group('evidence assembly', () {
    test("the signal's own context entries are always included alongside "
        "the matched rule's own evidence", () {
      final result = engine.classify(
        _signal(
          Exception('FOREIGN KEY constraint failed'),
          context: {'Product ID': '184', 'Sale ID': 'abc'},
        ),
      );
      expect(result.evidence.any((e) => e.label == 'Product ID' && e.value == '184'), isTrue);
      expect(result.evidence.any((e) => e.label == 'Sale ID' && e.value == 'abc'), isTrue);
      expect(result.evidence.any((e) => e.value == 'FOREIGN KEY'), isTrue);
    });

    test('context entries are preserved even when no rule matches', () {
      final result = engine.classify(
        _signal(Exception('totally novel'), context: {'Custom': 'value'}),
      );
      expect(result.evidence.single.label, 'Custom');
    });
  });
}
