import 'package:fulus_mobile/core/diagnostics/diagnostic_logger.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_enums.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_event.dart';
import 'package:fulus_mobile/core/diagnostics/storage/diagnostic_store.dart';
import 'package:fulus_mobile/core/diagnostics/storage/fallback_diagnostic_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Avoids any real file I/O (FallbackDiagnosticStore's real
/// implementation goes through path_provider, a platform channel this
/// plain `test()`-based file has no reason to set up) while still
/// exercising DiagnosticLogger's own orchestration logic around it.
class _InMemoryFallbackStore implements FallbackDiagnosticStore {
  final List<DiagnosticEvent> entries = [];
  bool appendShouldFail = false;

  @override
  Future<bool> append(DiagnosticEvent event) async {
    if (appendShouldFail) return false;
    entries.add(event);
    return true;
  }

  @override
  Future<List<DiagnosticEvent>> drainAll() async {
    final copy = List<DiagnosticEvent>.from(entries);
    entries.clear();
    return copy;
  }

  @override
  Future<bool> get hasPendingEntries async => entries.isNotEmpty;
}

/// A [DiagnosticStore] whose every method throws — the specific
/// scenario the logger's own header comment calls out as the whole
/// reason FallbackDiagnosticStore exists: the store being diagnosed
/// *is* the thing that's broken.
class _ThrowingStore implements DiagnosticStore {
  @override
  Future<bool> save(DiagnosticEvent event) => throw Exception('store is broken');
  @override
  Stream<List<DiagnosticEvent>> watchEvents({DiagnosticFilter filter = const DiagnosticFilter(), int limit = 200}) =>
      throw Exception('store is broken');
  @override
  Future<DiagnosticEvent?> getById(String id) => throw Exception('store is broken');
  @override
  Future<DiagnosticSummary> getSummary() => throw Exception('store is broken');
  @override
  Future<void> markViewed(String id) => throw Exception('store is broken');
  @override
  Future<List<DiagnosticEvent>> getForExport({DiagnosticFilter filter = const DiagnosticFilter()}) =>
      throw Exception('store is broken');
  @override
  Future<void> applyRetentionPolicy({required Duration olderThan, required int keepAtLeast}) =>
      throw Exception('store is broken');
  @override
  Future<void> deleteAll() => throw Exception('store is broken');
}

/// A well-behaved in-memory store, for the "everything works normally"
/// tests.
class _InMemoryStore implements DiagnosticStore {
  final List<DiagnosticEvent> saved = [];

  @override
  Future<bool> save(DiagnosticEvent event) async {
    saved.add(event);
    return true;
  }

  @override
  Stream<List<DiagnosticEvent>> watchEvents({DiagnosticFilter filter = const DiagnosticFilter(), int limit = 200}) =>
      Stream.value(saved);
  @override
  Future<DiagnosticEvent?> getById(String id) async {
    for (final e in saved) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<DiagnosticSummary> getSummary() async => DiagnosticSummary(
        errorCount: saved.where((e) => e.severity == DiagnosticSeverity.error).length,
        warningCount: saved.where((e) => e.severity == DiagnosticSeverity.warning).length,
        totalCount: saved.length,
        lastErrorAt: null,
      );
  @override
  Future<void> markViewed(String id) async {}
  @override
  Future<List<DiagnosticEvent>> getForExport({DiagnosticFilter filter = const DiagnosticFilter()}) async => saved;
  @override
  Future<void> applyRetentionPolicy({required Duration olderThan, required int keepAtLeast}) async {}
  @override
  Future<void> deleteAll() async => saved.clear();
}

/// A store whose `save` always fails (returns false, doesn't throw) —
/// the "primary store is attached but this particular write failed"
/// case, as opposed to `_ThrowingStore`'s "the store itself is broken"
/// case. Both must route to the fallback.
class _FailingSaveStore extends _InMemoryStore {
  @override
  Future<bool> save(DiagnosticEvent event) async => false;
}

void main() {
  group('captureError never throws', () {
    test('when no primary store is attached at all', () async {
      final fallback = _InMemoryFallbackStore();
      final logger = DiagnosticLogger(fallbackStore: fallback);

      final event = await logger.captureError(
        error: Exception('boom'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.sales,
      );

      expect(event.title, isNotEmpty);
      expect(fallback.entries, hasLength(1));
    });

    test('when the primary store throws on every call', () async {
      final fallback = _InMemoryFallbackStore();
      final logger = DiagnosticLogger(fallbackStore: fallback);
      logger.attachStore(_ThrowingStore());

      // The real test: this must complete without throwing.
      final event = await logger.captureError(
        error: Exception('boom'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.critical,
        category: DiagnosticCategory.database,
      );
      expect(event, isNotNull);
    });

    test('when the primary store returns false (a clean, non-throwing '
        'failure) — falls back rather than losing the event', () async {
      final fallback = _InMemoryFallbackStore();
      final logger = DiagnosticLogger(fallbackStore: fallback);
      logger.attachStore(_FailingSaveStore());

      await logger.captureError(
        error: Exception('boom'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.sales,
      );
      expect(fallback.entries, hasLength(1));
    });

    test('even when the fallback store ALSO fails, captureError still '
        'returns rather than throwing', () async {
      final fallback = _InMemoryFallbackStore()..appendShouldFail = true;
      final logger = DiagnosticLogger(fallbackStore: fallback);
      logger.attachStore(_ThrowingStore());

      final event = await logger.captureError(
        error: Exception('boom'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.sales,
      );
      expect(event, isNotNull);
    });
  });

  group('breadcrumb never throws', () {
    test('with normal input', () {
      final logger = DiagnosticLogger(fallbackStore: _InMemoryFallbackStore());
      expect(() => logger.breadcrumb('Product added to cart'), returnsNormally);
    });

    test('with a very large data map', () {
      final logger = DiagnosticLogger(fallbackStore: _InMemoryFallbackStore());
      final data = {for (var i = 0; i < 1000; i++) 'key$i': 'value$i'};
      expect(() => logger.breadcrumb('stress test', data: data), returnsNormally);
    });
  });

  group('successful capture, end to end', () {
    test('a real store attached, real classification, real redaction', () async {
      final store = _InMemoryStore();
      final logger = DiagnosticLogger(fallbackStore: _InMemoryFallbackStore());
      logger.attachStore(store);

      logger.breadcrumb('Sale transaction started', category: DiagnosticCategory.sales);
      final event = await logger.captureError(
        error: Exception('FOREIGN KEY constraint failed'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.sales,
        component: 'DraftCartRepositoryImpl',
        context: {'password': 'shouldNeverAppear', 'Sale ID': 'abc'},
      );

      expect(store.saved, hasLength(1));
      // Root-cause engine actually ran: a FOREIGN KEY exception gets a
      // specific, high-confidence cause, not UNKNOWN.
      expect(event.cause.confidence, DiagnosticConfidence.high);
      // Redaction actually ran on the way to storage.
      expect(event.evidence.any((e) => e.value == 'shouldNeverAppear'), isFalse);
      expect(event.evidence.any((e) => e.label == 'Sale ID' && e.value == 'abc'), isTrue);
      // The breadcrumb recorded just before capture is on the event.
      expect(event.breadcrumbs.any((b) => b.message == 'Sale transaction started'), isTrue);
    });

    test('draining the fallback: entries queued before attachStore are '
        'moved into the primary store once it is attached', () async {
      final fallback = _InMemoryFallbackStore();
      final logger = DiagnosticLogger(fallbackStore: fallback);

      await logger.captureError(
        error: Exception('early failure, before the store exists'),
        stackTrace: StackTrace.current,
        severity: DiagnosticSeverity.critical,
        category: DiagnosticCategory.startup,
      );
      expect(fallback.entries, hasLength(1));

      final store = _InMemoryStore();
      logger.attachStore(store);
      // attachStore's drain is fire-and-forget; give it a turn.
      await Future<void>.delayed(Duration.zero);

      expect(store.saved, hasLength(1));
      expect((await fallback.hasPendingEntries), isFalse);
    });
  });

  group('read passthroughs before attachStore', () {
    test('return safe empty defaults rather than throwing', () async {
      final logger = DiagnosticLogger(fallbackStore: _InMemoryFallbackStore());
      expect(await logger.getById('anything'), isNull);
      expect((await logger.getSummary()).totalCount, 0);
      expect(await logger.getForExport(), isEmpty);
      // Must not throw.
      await logger.markViewed('anything');
      await logger.deleteAll();
      await logger.applyRetentionPolicy();
    });
  });
}
