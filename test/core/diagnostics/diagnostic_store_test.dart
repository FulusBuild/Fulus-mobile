import 'package:drift/native.dart';
import 'package:fulus_mobile/core/diagnostics/models/breadcrumb.dart';
import 'package:fulus_mobile/core/diagnostics/models/device_context.dart';
import 'package:fulus_mobile/core/diagnostics/models/diagnostic_event.dart';
import 'package:fulus_mobile/core/diagnostics/storage/drift_diagnostic_store.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

DiagnosticEvent _event({
  String id = 'evt-1',
  DiagnosticSeverity severity = DiagnosticSeverity.error,
  DiagnosticCategory category = DiagnosticCategory.sales,
  String title = 'Sale failed',
  String? component,
  String? operation,
  DateTime? timestamp,
}) {
  return DiagnosticEvent(
    id: id,
    severity: severity,
    category: category,
    title: title,
    message: 'Something went wrong.',
    component: component,
    operation: operation,
    timestamp: timestamp,
    cause: const DiagnosticCause(description: 'Test cause', confidence: DiagnosticConfidence.high),
    evidence: const [EvidenceItem('Sale ID', 'abc123')],
    breadcrumbs: [Breadcrumb(message: 'Sale transaction started')],
    device: const DeviceContext.unknown(),
  );
}

void main() {
  late AppDatabase db;
  late DriftDiagnosticStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftDiagnosticStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('save + getById', () {
    test('a saved event round-trips through getById unchanged in its key fields', () async {
      final ok = await store.save(_event());
      expect(ok, isTrue);

      final fetched = await store.getById('evt-1');
      expect(fetched, isNotNull);
      expect(fetched!.title, 'Sale failed');
      expect(fetched.severity, DiagnosticSeverity.error);
      expect(fetched.category, DiagnosticCategory.sales);
      expect(fetched.cause.description, 'Test cause');
      expect(fetched.evidence.single.label, 'Sale ID');
      expect(fetched.breadcrumbs.single.message, 'Sale transaction started');
    });

    test('getById returns null for an id that does not exist', () async {
      final fetched = await store.getById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('duplicate-event handling', () {
    test('the same title/component/operation/exceptionType within the window '
        'bumps occurrenceCount instead of inserting a new row', () async {
      final now = DateTime.now();
      await store.save(_event(
        id: 'evt-a',
        component: 'DraftCartRepositoryImpl',
        operation: 'completeSale',
        timestamp: now,
      ));
      await store.save(_event(
        id: 'evt-b',
        component: 'DraftCartRepositoryImpl',
        operation: 'completeSale',
        timestamp: now.add(const Duration(seconds: 30)),
      ));

      final all = await store.getForExport();
      expect(all.length, 1);
      expect(all.single.occurrenceCount, 2);
    });

    test('a different component does NOT get merged, even with the same title', () async {
      final now = DateTime.now();
      await store.save(_event(id: 'evt-a', component: 'ComponentA', timestamp: now));
      await store.save(_event(id: 'evt-b', component: 'ComponentB', timestamp: now));

      final all = await store.getForExport();
      expect(all.length, 2);
    });
  });

  group('getSummary', () {
    test('counts errors, warnings, and total correctly', () async {
      await store.save(_event(id: '1', severity: DiagnosticSeverity.error));
      await store.save(_event(id: '2', severity: DiagnosticSeverity.critical));
      await store.save(_event(id: '3', severity: DiagnosticSeverity.warning));
      await store.save(_event(id: '4', severity: DiagnosticSeverity.info));

      final summary = await store.getSummary();
      expect(summary.errorCount, 2); // error + critical
      expect(summary.warningCount, 1);
      expect(summary.totalCount, 4);
      expect(summary.lastErrorAt, isNotNull);
    });

    test('an empty store returns DiagnosticSummary.empty-shaped zeros', () async {
      final summary = await store.getSummary();
      expect(summary.errorCount, 0);
      expect(summary.warningCount, 0);
      expect(summary.totalCount, 0);
      expect(summary.lastErrorAt, isNull);
    });
  });

  group('filtering', () {
    test('getForExport filters by severity', () async {
      await store.save(_event(id: '1', severity: DiagnosticSeverity.error));
      await store.save(_event(id: '2', severity: DiagnosticSeverity.warning));

      final errorsOnly = await store.getForExport(
        filter: const DiagnosticFilter(severities: {DiagnosticSeverity.error}),
      );
      expect(errorsOnly.length, 1);
      expect(errorsOnly.single.id, '1');
    });

    test('getForExport filters by category', () async {
      await store.save(_event(id: '1', category: DiagnosticCategory.sales));
      await store.save(_event(id: '2', category: DiagnosticCategory.synchronization));

      final salesOnly = await store.getForExport(
        filter: const DiagnosticFilter(categories: {DiagnosticCategory.sales}),
      );
      expect(salesOnly.length, 1);
      expect(salesOnly.single.id, '1');
    });

    test('getForExport filters by date range', () async {
      final now = DateTime.now();
      await store.save(_event(id: 'old', timestamp: now.subtract(const Duration(days: 10))));
      await store.save(_event(id: 'recent', timestamp: now));

      final recentOnly = await store.getForExport(
        filter: DiagnosticFilter(startDate: now.subtract(const Duration(days: 1))),
      );
      expect(recentOnly.length, 1);
      expect(recentOnly.single.id, 'recent');
    });

    test('getForExport filters by free-text search across title/message/component', () async {
      await store.save(_event(id: '1', title: 'Sale failed', component: 'DraftCartRepositoryImpl'));
      await store.save(_event(id: '2', title: 'Sync failed', component: 'SyncEngine'));

      final results = await store.getForExport(filter: const DiagnosticFilter(searchText: 'sync'));
      expect(results.length, 1);
      expect(results.single.id, '2');
    });
  });

  group('markViewed', () {
    test('updates lifecycleStatus to viewed and never throws for a missing id', () async {
      await store.save(_event(id: '1'));
      await store.markViewed('1');
      final fetched = await store.getById('1');
      expect(fetched!.lifecycleStatus, DiagnosticLifecycleStatus.viewed);

      // Must not throw for a non-existent id.
      await store.markViewed('does-not-exist');
    });
  });

  group('applyRetentionPolicy', () {
    test('never deletes any of the most recent keepAtLeast rows, regardless of age', () async {
      final veryOld = DateTime.now().subtract(const Duration(days: 400));
      for (var i = 0; i < 5; i++) {
        await store.save(_event(id: 'evt-$i', timestamp: veryOld.add(Duration(seconds: i))));
      }

      await store.applyRetentionPolicy(olderThan: const Duration(days: 30), keepAtLeast: 5);

      final remaining = await store.getForExport();
      expect(remaining.length, 5);
    });

    test('deletes rows beyond keepAtLeast that are also older than olderThan', () async {
      final veryOld = DateTime.now().subtract(const Duration(days: 400));
      final recent = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await store.save(_event(id: 'old-$i', timestamp: veryOld.add(Duration(seconds: i))));
      }
      for (var i = 0; i < 3; i++) {
        await store.save(_event(id: 'new-$i', timestamp: recent.add(Duration(seconds: i))));
      }

      await store.applyRetentionPolicy(olderThan: const Duration(days: 30), keepAtLeast: 3);

      final remaining = await store.getForExport();
      expect(remaining.length, 3);
      expect(remaining.every((e) => e.id.startsWith('new-')), isTrue);
    });
  });

  group('deleteAll', () {
    test('removes every event', () async {
      await store.save(_event(id: '1'));
      await store.save(_event(id: '2'));
      await store.deleteAll();
      final remaining = await store.getForExport();
      expect(remaining, isEmpty);
    });
  });
}
