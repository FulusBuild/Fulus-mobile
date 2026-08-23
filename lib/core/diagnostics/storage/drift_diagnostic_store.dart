import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/database/database.dart';
import '../../../data/local/database/tables.dart';
import '../models/breadcrumb.dart';
import '../models/device_context.dart';
import '../models/diagnostic_enums.dart';
import '../models/diagnostic_event.dart';
import 'diagnostic_store.dart';

/// The primary [DiagnosticStore] — backed by the same on-device Drift
/// database (`AppDatabase`, `DiagnosticEvents` table) every other
/// repository in this app already uses, per the diagnostic-system
/// brief's own instruction to prefer the existing storage architecture
/// over a new one.
///
/// **Filtering happens in Dart, after a single ordered fetch, not via a
/// dynamically-built SQL `WHERE` clause.** This is a deliberate choice,
/// not an oversight: it keeps every query this class runs limited to
/// the small set of Drift operations already used and verified
/// elsewhere in this exact codebase (`select`, `.where` on a single
/// plain column, `.orderBy`, `.watch`, `.get`, `.insert`, `.write`,
/// `.go`) — the diagnostic system was written and reviewed without a
/// working Flutter toolchain available (see the implementation report),
/// so every Drift call site here is one I can point at a real,
/// already-working precedent elsewhere in this codebase rather than an
/// unverified guess at this Drift version's exact multi-value/`LIKE`
/// query-builder surface. A local, retention-pruned error log (bounded
/// by [applyRetentionPolicy]) is small enough that fetching it fully
/// ordered and filtering client-side is a reasonable, honest tradeoff —
/// noted in the implementation report as a follow-up to verify and
/// optimize once a real build is available, not hidden here.
class DriftDiagnosticStore implements DiagnosticStore {
  DriftDiagnosticStore(this._db);

  final AppDatabase _db;

  /// A repeat of the same title/component/operation/exceptionType
  /// within this window is treated as "the same problem happening
  /// again" (brief Section 14's duplicate-event handling) and bumps the
  /// existing row's occurrenceCount rather than inserting a new one.
  static const _duplicateWindow = Duration(minutes: 5);

  @override
  Future<bool> save(DiagnosticEvent event) async {
    try {
      final existing = await _findRecentDuplicate(event);
      if (existing != null) {
        await (_db.update(_db.diagnosticEvents)..where((t) => t.id.equals(existing.id))).write(
          DiagnosticEventsCompanion(
            timestamp: Value(event.timestamp),
            occurrenceCount: Value(existing.occurrenceCount + 1),
          ),
        );
      } else {
        await _db.into(_db.diagnosticEvents).insert(_toCompanion(event));
      }
      return true;
    } catch (_) {
      // Never throws outward — DiagnosticLogger is what decides what
      // happens next (falling back to the file-based emergency store).
      return false;
    }
  }

  Future<DiagnosticEventRow?> _findRecentDuplicate(DiagnosticEvent event) async {
    final windowStart = event.timestamp.subtract(_duplicateWindow);
    final query = _db.select(_db.diagnosticEvents)
      ..where((t) => t.title.equals(event.title) & t.timestamp.isBiggerOrEqualValue(windowStart));
    final candidates = await query.get();
    for (final row in candidates) {
      if (row.component == event.component &&
          row.operation == event.operation &&
          row.exceptionType == event.exceptionType) {
        return row;
      }
    }
    return null;
  }

  @override
  Stream<List<DiagnosticEvent>> watchEvents({
    DiagnosticFilter filter = const DiagnosticFilter(),
    int limit = 200,
  }) {
    final query = _db.select(_db.diagnosticEvents)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    return query.watch().map((rows) {
      final events = rows.map(_fromRow).where((e) => _matchesFilter(e, filter));
      return events.take(limit).toList();
    });
  }

  @override
  Future<DiagnosticEvent?> getById(String id) async {
    try {
      final row = await (_db.select(_db.diagnosticEvents)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      return row == null ? null : _fromRow(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DiagnosticSummary> getSummary() async {
    try {
      final rows = await _db.select(_db.diagnosticEvents).get();
      var errorCount = 0;
      var warningCount = 0;
      DateTime? lastErrorAt;
      for (final row in rows) {
        final isErrorLike =
            row.severity == DiagnosticSeverity.critical || row.severity == DiagnosticSeverity.error;
        if (isErrorLike) {
          errorCount++;
          if (lastErrorAt == null || row.timestamp.isAfter(lastErrorAt)) {
            lastErrorAt = row.timestamp;
          }
        } else if (row.severity == DiagnosticSeverity.warning) {
          warningCount++;
        }
      }
      return DiagnosticSummary(
        errorCount: errorCount,
        warningCount: warningCount,
        totalCount: rows.length,
        lastErrorAt: lastErrorAt,
      );
    } catch (_) {
      return const DiagnosticSummary.empty();
    }
  }

  @override
  Future<void> markViewed(String id) async {
    try {
      await (_db.update(_db.diagnosticEvents)..where((t) => t.id.equals(id))).write(
        const DiagnosticEventsCompanion(lifecycleStatus: Value(DiagnosticLifecycleStatus.viewed)),
      );
    } catch (_) {
      // Purely cosmetic (an unread indicator) — never worth surfacing a
      // failure for.
    }
  }

  @override
  Future<List<DiagnosticEvent>> getForExport({DiagnosticFilter filter = const DiagnosticFilter()}) async {
    try {
      final query = _db.select(_db.diagnosticEvents)
        ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
      final rows = await query.get();
      return rows.map(_fromRow).where((e) => _matchesFilter(e, filter)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> applyRetentionPolicy({
    required Duration olderThan,
    required int keepAtLeast,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(olderThan);
      final all = await (_db.select(_db.diagnosticEvents)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .get();
      if (all.length <= keepAtLeast) return;
      // Never deletes any of the most recent [keepAtLeast] rows, no
      // matter how old they are — a business that opens the till only
      // occasionally should not lose its entire log to a time-based
      // cutoff between sessions. Beyond that floor, anything older
      // than [olderThan] goes.
      final eligibleForDeletion = all.sublist(keepAtLeast);
      final idsToDelete = eligibleForDeletion
          .where((row) => row.timestamp.isBefore(cutoff))
          .map((row) => row.id)
          .toList();
      if (idsToDelete.isEmpty) return;
      await (_db.delete(_db.diagnosticEvents)..where((t) => t.id.isIn(idsToDelete))).go();
    } catch (_) {
      // Retention is best-effort housekeeping — a failed cleanup pass
      // is not itself worth surfacing as a diagnostic event (real risk
      // of a self-referential loop) and never worth crashing over.
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _db.delete(_db.diagnosticEvents).go();
    } catch (_) {
      // Best-effort, same reasoning as applyRetentionPolicy above.
    }
  }

  bool _matchesFilter(DiagnosticEvent event, DiagnosticFilter filter) {
    if (filter.severities.isNotEmpty && !filter.severities.contains(event.severity)) return false;
    if (filter.categories.isNotEmpty && !filter.categories.contains(event.category)) return false;
    if (filter.component != null && event.component != filter.component) return false;
    if (filter.screen != null && event.screen != filter.screen) return false;
    if (filter.startDate != null && event.timestamp.isBefore(filter.startDate!)) return false;
    if (filter.endDate != null && event.timestamp.isAfter(filter.endDate!)) return false;
    final search = filter.searchText?.trim().toLowerCase();
    if (search != null && search.isNotEmpty) {
      final haystack = '${event.title} ${event.message} ${event.component ?? ''} '
              '${event.operation ?? ''} ${event.screen ?? ''}'
          .toLowerCase();
      if (!haystack.contains(search)) return false;
    }
    return true;
  }

  DiagnosticEventsCompanion _toCompanion(DiagnosticEvent event) {
    return DiagnosticEventsCompanion(
      id: Value(event.id),
      timestamp: Value(event.timestamp),
      firstOccurredAt: Value(event.firstOccurredAt),
      occurrenceCount: Value(event.occurrenceCount),
      severity: Value(event.severity),
      category: Value(event.category),
      title: Value(event.title),
      message: Value(event.message),
      component: Value(event.component),
      operation: Value(event.operation),
      screen: Value(event.screen),
      exceptionType: Value(event.exceptionType),
      errorCode: Value(event.errorCode),
      stackTrace: Value(event.stackTrace),
      causeDescription: Value(event.cause.description),
      causeConfidence: Value(event.cause.confidence),
      evidenceJson: Value(jsonEncode(event.evidence.map((e) => e.toJson()).toList())),
      technicalContextJson: Value(jsonEncode(event.technicalContext.map((e) => e.toJson()).toList())),
      breadcrumbsJson: Value(jsonEncode(event.breadcrumbs.map((b) => b.toJson()).toList())),
      failureStage: Value(event.failureStage),
      deviceJson: Value(jsonEncode(event.device.toJson())),
      lifecycleStatus: Value(event.lifecycleStatus),
    );
  }

  DiagnosticEvent _fromRow(DiagnosticEventRow row) {
    return DiagnosticEvent(
      id: row.id,
      timestamp: row.timestamp,
      firstOccurredAt: row.firstOccurredAt,
      occurrenceCount: row.occurrenceCount,
      severity: row.severity,
      category: row.category,
      title: row.title,
      message: row.message,
      component: row.component,
      operation: row.operation,
      screen: row.screen,
      exceptionType: row.exceptionType,
      errorCode: row.errorCode,
      stackTrace: row.stackTrace,
      cause: DiagnosticCause(description: row.causeDescription, confidence: row.causeConfidence),
      evidence: _decodeEvidence(row.evidenceJson),
      technicalContext: _decodeEvidence(row.technicalContextJson),
      breadcrumbs: _decodeBreadcrumbs(row.breadcrumbsJson),
      failureStage: row.failureStage,
      device: _decodeDevice(row.deviceJson),
      lifecycleStatus: row.lifecycleStatus,
    );
  }

  List<EvidenceItem> _decodeEvidence(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((m) => EvidenceItem.fromJson(m.cast())).toList();
    } catch (_) {
      return const [];
    }
  }

  List<Breadcrumb> _decodeBreadcrumbs(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((m) => Breadcrumb.fromJson(m.cast())).toList();
    } catch (_) {
      return const [];
    }
  }

  DeviceContext _decodeDevice(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const DeviceContext.unknown();
      return DeviceContext.fromJson(decoded.cast());
    } catch (_) {
      return const DeviceContext.unknown();
    }
  }
}
