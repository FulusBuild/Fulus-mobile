import 'breadcrumb.dart';
import 'device_context.dart';
import 'diagnostic_enums.dart';

/// One labeled fact backing either a [DiagnosticCause] ("Product ID:
/// 184") or supplementary technical context ("Connectivity: offline").
/// A plain label/value pair rather than a map so ordering is preserved
/// — the evidence list is meant to read top-to-bottom the way the brief
/// itself always presents it, and a `Map` has no guaranteed order once
/// it round-trips through JSON.
class EvidenceItem {
  const EvidenceItem(this.label, this.value);

  final String label;
  final String value;

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  factory EvidenceItem.fromJson(Map<String, Object?> json) =>
      EvidenceItem(json['label'] as String? ?? '', json['value'] as String? ?? '');

  @override
  String toString() => '$label: $value';
}

/// The root-cause engine's conclusion. [DiagnosticCause.unknown] is the
/// deliberate, honest default — every rule in engine/rules/ falls back
/// to it rather than guessing, per the brief's explicit "say UNKNOWN
/// rather than inventing a cause" requirement.
class DiagnosticCause {
  const DiagnosticCause({required this.description, required this.confidence});

  const DiagnosticCause.unknown()
      : description = 'Unable to determine automatically.',
        confidence = DiagnosticConfidence.unknown;

  final String description;
  final DiagnosticConfidence confidence;

  Map<String, Object?> toJson() => {'description': description, 'confidence': confidence.name};

  factory DiagnosticCause.fromJson(Map<String, Object?> json) {
    final confidenceName = json['confidence'] as String?;
    return DiagnosticCause(
      description: json['description'] as String? ?? 'Unable to determine automatically.',
      confidence: DiagnosticConfidence.values
          .firstWhere((c) => c.name == confidenceName, orElse: () => DiagnosticConfidence.unknown),
    );
  }
}

/// A single structured diagnostic record — the thing captured at a
/// failure boundary, persisted locally, listed on the Diagnostics
/// screen, and (optionally) shared. See this module's own top-level
/// design note in diagnostic_logger.dart for how an instance of this
/// gets built.
///
/// Deliberately NOT a Drift row class itself — this type has no
/// dependency on `package:drift` at all, matching how domain entities
/// elsewhere in this codebase (e.g. `domain/entities/sale.dart`) stay
/// persistence-agnostic and leave the `toCompanion`/`fromRow` mapping to
/// a dedicated mapper next to the store that needs it
/// (storage/drift_diagnostic_store.dart) — this model is just as usable
/// from a pure-Dart unit test or the file-based fallback store as it is
/// from the Drift-backed one.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.message,
    DateTime? timestamp,
    DateTime? firstOccurredAt,
    this.occurrenceCount = 1,
    this.component,
    this.operation,
    this.screen,
    this.exceptionType,
    this.errorCode,
    this.stackTrace,
    DiagnosticCause? cause,
    List<EvidenceItem>? evidence,
    List<EvidenceItem>? technicalContext,
    List<Breadcrumb>? breadcrumbs,
    this.failureStage,
    DeviceContext? device,
    this.lifecycleStatus = DiagnosticLifecycleStatus.captured,
  })  : timestamp = timestamp ?? DateTime.now(),
        firstOccurredAt = firstOccurredAt ?? timestamp ?? DateTime.now(),
        cause = cause ?? const DiagnosticCause.unknown(),
        evidence = evidence == null ? const [] : List.unmodifiable(evidence),
        technicalContext = technicalContext == null ? const [] : List.unmodifiable(technicalContext),
        breadcrumbs = breadcrumbs == null ? const [] : List.unmodifiable(breadcrumbs),
        device = device ?? const DeviceContext.unknown();

  /// ULID — sortable by creation time, matching how every other local
  /// ID in this codebase is generated (see pubspec.yaml's own comment
  /// on why ULID over uuid).
  final String id;

  /// Most recent occurrence — what the list sorts and displays by.
  final DateTime timestamp;

  /// First occurrence — preserved even after [occurrenceCount] grows,
  /// so "this has been happening since..." stays answerable.
  final DateTime firstOccurredAt;

  /// Duplicate-event handling (brief Section 14): a repeat of the same
  /// title/component/operation/exceptionType within a short window
  /// bumps this and [timestamp] rather than inserting a new row — see
  /// storage/drift_diagnostic_store.dart's own save() for the matching
  /// logic. Never itself a reason to hide the event; it's additive
  /// information ("this keeps happening"), shown alongside it.
  final int occurrenceCount;

  final DiagnosticSeverity severity;
  final DiagnosticCategory category;

  /// Short, human title — "Sale failed". Never a raw exception string.
  final String title;

  /// One more line of plain-language context — "Database transaction
  /// failed". Still never a raw exception message; see
  /// diagnostic_logger.dart on where the raw exception actually goes
  /// (technicalContext/stackTrace, both behind the UI's "expand"
  /// affordance, never the headline).
  final String message;

  /// e.g. "SalesRepository", "InventoryRepository".
  final String? component;

  /// e.g. "completeSale()".
  final String? operation;

  /// e.g. "SellScreen" — the screen active when this was captured, when
  /// known. Null for events with no meaningful screen (a background
  /// sync failure with nothing on-screen at the time).
  final String? screen;

  /// The caught exception/error's own `runtimeType.toString()`.
  final String? exceptionType;

  /// A short machine-readable code where one genuinely exists (a SQLite
  /// result code, an HTTP status, a platform-channel error code) —
  /// null when nothing like that applies.
  final String? errorCode;

  /// Truncated per DiagnosticRedactor/the logger's own size bound — see
  /// diagnostic_logger.dart's `_maxStackTraceChars`.
  final String? stackTrace;

  final DiagnosticCause cause;

  /// The bullet points backing [cause] specifically — shown in the
  /// detail screen's prominent "Evidence" section.
  final List<EvidenceItem> evidence;

  /// Supplementary technical facts (device/db/network/sync state at
  /// capture time) that aren't themselves cause evidence — shown folded
  /// into the detail screen's "Technical details" section instead.
  final List<EvidenceItem> technicalContext;

  /// Snapshot of BreadcrumbTrail's recent history at the moment this was
  /// captured — "Recent activity" in the detail screen.
  final List<Breadcrumb> breadcrumbs;

  /// e.g. "5 — Update inventory" — set by DiagnosticOperation.fail()
  /// when the failure happened inside a tracked multi-step operation;
  /// null for events captured outside one (a global Flutter framework
  /// error has no operation stage to report).
  final String? failureStage;

  final DeviceContext device;

  /// captured/stored/viewed/shared today; pendingSync/synced/syncFailed
  /// are reserved for a future remote-telemetry layer this phase
  /// deliberately does not build (brief Section 13) — persisted now so
  /// that layer, if it ever exists, is additive rather than a schema
  /// migration away from records already on real devices.
  final DiagnosticLifecycleStatus lifecycleStatus;

  bool get isFailure =>
      severity == DiagnosticSeverity.critical || severity == DiagnosticSeverity.error;

  DiagnosticEvent copyWith({
    int? occurrenceCount,
    DateTime? timestamp,
    DiagnosticLifecycleStatus? lifecycleStatus,
  }) {
    return DiagnosticEvent(
      id: id,
      severity: severity,
      category: category,
      title: title,
      message: message,
      timestamp: timestamp ?? this.timestamp,
      firstOccurredAt: firstOccurredAt,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      component: component,
      operation: operation,
      screen: screen,
      exceptionType: exceptionType,
      errorCode: errorCode,
      stackTrace: stackTrace,
      cause: cause,
      evidence: evidence,
      technicalContext: technicalContext,
      breadcrumbs: breadcrumbs,
      failureStage: failureStage,
      device: device,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'firstOccurredAt': firstOccurredAt.toIso8601String(),
        'occurrenceCount': occurrenceCount,
        'severity': severity.name,
        'category': category.name,
        'title': title,
        'message': message,
        'component': component,
        'operation': operation,
        'screen': screen,
        'exceptionType': exceptionType,
        'errorCode': errorCode,
        'stackTrace': stackTrace,
        'cause': cause.toJson(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'technicalContext': technicalContext.map((e) => e.toJson()).toList(),
        'breadcrumbs': breadcrumbs.map((b) => b.toJson()).toList(),
        'failureStage': failureStage,
        'device': device.toJson(),
        'lifecycleStatus': lifecycleStatus.name,
      };

  factory DiagnosticEvent.fromJson(Map<String, Object?> json) {
    DiagnosticSeverity severity = DiagnosticSeverity.values.firstWhere(
      (s) => s.name == json['severity'],
      orElse: () => DiagnosticSeverity.error,
    );
    DiagnosticCategory category = DiagnosticCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => DiagnosticCategory.unknown,
    );
    DiagnosticLifecycleStatus lifecycle = DiagnosticLifecycleStatus.values.firstWhere(
      (s) => s.name == json['lifecycleStatus'],
      orElse: () => DiagnosticLifecycleStatus.stored,
    );
    final evidenceRaw = json['evidence'];
    final technicalRaw = json['technicalContext'];
    final breadcrumbsRaw = json['breadcrumbs'];
    final causeRaw = json['cause'];
    final deviceRaw = json['device'];

    return DiagnosticEvent(
      id: json['id'] as String? ?? '',
      severity: severity,
      category: category,
      title: json['title'] as String? ?? 'Unknown issue',
      message: json['message'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? ''),
      firstOccurredAt: DateTime.tryParse(json['firstOccurredAt'] as String? ?? ''),
      occurrenceCount: json['occurrenceCount'] as int? ?? 1,
      component: json['component'] as String?,
      operation: json['operation'] as String?,
      screen: json['screen'] as String?,
      exceptionType: json['exceptionType'] as String?,
      errorCode: json['errorCode'] as String?,
      stackTrace: json['stackTrace'] as String?,
      cause: causeRaw is Map
          ? DiagnosticCause.fromJson(causeRaw.cast<String, Object?>())
          : const DiagnosticCause.unknown(),
      evidence: evidenceRaw is List
          ? evidenceRaw.whereType<Map>().map((m) => EvidenceItem.fromJson(m.cast())).toList()
          : null,
      technicalContext: technicalRaw is List
          ? technicalRaw.whereType<Map>().map((m) => EvidenceItem.fromJson(m.cast())).toList()
          : null,
      breadcrumbs: breadcrumbsRaw is List
          ? breadcrumbsRaw.whereType<Map>().map((m) => Breadcrumb.fromJson(m.cast())).toList()
          : null,
      failureStage: json['failureStage'] as String?,
      device: deviceRaw is Map ? DeviceContext.fromJson(deviceRaw.cast()) : null,
      lifecycleStatus: lifecycle,
    );
  }
}

/// The Diagnostics screen's header counts — "3 Errors / 12 Warnings /
/// 48 Events" plus "Last error 2 minutes ago". [totalCount] is a true
/// total (every severity, including info-level events), so it is
/// expected to be >= errorCount + warningCount, never presented as if
/// it were a third, disjoint bucket.
class DiagnosticSummary {
  const DiagnosticSummary({
    required this.errorCount,
    required this.warningCount,
    required this.totalCount,
    this.lastErrorAt,
  });

  const DiagnosticSummary.empty()
      : errorCount = 0,
        warningCount = 0,
        totalCount = 0,
        lastErrorAt = null;

  /// critical + error severities combined — one number, matching how
  /// the brief's own mockup shows a single "Errors" line rather than
  /// splitting critical out separately.
  final int errorCount;
  final int warningCount;
  final int totalCount;
  final DateTime? lastErrorAt;
}

/// The Diagnostics screen's current filter/search selection. All fields
/// are "AND"ed together; an empty/null field means "no restriction on
/// this dimension". Passed to DiagnosticStore.watchEvents.
class DiagnosticFilter {
  const DiagnosticFilter({
    this.severities = const {},
    this.categories = const {},
    this.component,
    this.screen,
    this.startDate,
    this.endDate,
    this.searchText,
  });

  final Set<DiagnosticSeverity> severities;
  final Set<DiagnosticCategory> categories;
  final String? component;
  final String? screen;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? searchText;

  bool get isEmpty =>
      severities.isEmpty &&
      categories.isEmpty &&
      component == null &&
      screen == null &&
      startDate == null &&
      endDate == null &&
      (searchText == null || searchText!.trim().isEmpty);

  DiagnosticFilter copyWith({
    Set<DiagnosticSeverity>? severities,
    Set<DiagnosticCategory>? categories,
    String? Function()? component,
    String? Function()? screen,
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    String? Function()? searchText,
  }) {
    return DiagnosticFilter(
      severities: severities ?? this.severities,
      categories: categories ?? this.categories,
      component: component != null ? component() : this.component,
      screen: screen != null ? screen() : this.screen,
      startDate: startDate != null ? startDate() : this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      searchText: searchText != null ? searchText() : this.searchText,
    );
  }
}
