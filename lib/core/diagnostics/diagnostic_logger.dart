import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ulid/ulid.dart';

import '../errors/failure.dart';
import 'breadcrumbs/breadcrumb_trail.dart';
import 'capture/device_context_provider.dart';
import 'engine/diagnostic_signal.dart';
import 'engine/root_cause_engine.dart';
import 'models/diagnostic_enums.dart';
import 'models/diagnostic_event.dart';
import 'redaction/diagnostic_redactor.dart';
import 'storage/diagnostic_store.dart';
import 'storage/fallback_diagnostic_store.dart';

/// The single entry point the rest of the app talks to for
/// diagnostics — everything else in core/diagnostics/ is plumbing this
/// class owns and coordinates. One instance lives for the whole process
/// (see main.dart/bootstrap.dart for exactly when it's constructed and
/// wired up) and is reached from anywhere else in the app via
/// `diagnosticLoggerProvider` (app/providers.dart).
///
/// **This class's one non-negotiable rule: it must never itself throw,
/// and it must never make an application failure worse.** Per the
/// brief's own Section 15 ("the diagnostic system must never replace
/// one application failure with a second diagnostic failure"), every
/// public method here is wrapped in its own try/catch with a safe
/// fallback — a logging bug should degrade to "this one event didn't
/// get recorded", never to "the sale that was already failing now also
/// crashes the app". Working through this file top to bottom: even the
/// redactor, the breadcrumb trail, and the root-cause engine (all pure,
/// simple Dart with little real chance of throwing) are still called
/// from inside a guarded block, because "little chance" is not the same
/// promise as "cannot".
///
/// **What this class captures is deliberately narrower than "every
/// Failure the app ever throws".** This app already has a considered,
/// separate system for expected, already-handled outcomes — the sealed
/// `Failure` hierarchy (core/errors/failure.dart), shown to the user
/// inline at the point something like a validation error happens. This
/// class exists for the gap next to that system, not a replacement for
/// it: unhandled exceptions, infrastructure failures (database,
/// network, file system), and the small number of `Failure` occurrences
/// that reach a diagnostic capture point specifically *because* they
/// escaped their normal handling. Logging every routine, already-shown
/// `Failure` here as well would flood the log with expected outcomes
/// and bury the real signal — exactly the "no excessive logging during
/// normal operation" the brief's Section 14 asks this system to avoid.
class DiagnosticLogger {
  DiagnosticLogger({
    BreadcrumbTrail? breadcrumbTrail,
    RootCauseEngine? rootCauseEngine,
    DiagnosticRedactor? redactor,
    FallbackDiagnosticStore? fallbackStore,
    DeviceContextProvider? deviceContextProvider,
  })  : _breadcrumbTrail = breadcrumbTrail ?? BreadcrumbTrail(),
        _rootCauseEngine = rootCauseEngine ?? const RootCauseEngine(),
        _redactor = redactor ?? const DiagnosticRedactor(),
        _fallbackStore = fallbackStore ?? FallbackDiagnosticStore(),
        _deviceContextProvider = deviceContextProvider ?? DeviceContextProvider();

  final BreadcrumbTrail _breadcrumbTrail;
  final RootCauseEngine _rootCauseEngine;
  final DiagnosticRedactor _redactor;
  final FallbackDiagnosticStore _fallbackStore;
  final DeviceContextProvider _deviceContextProvider;

  /// Truncation bound for a captured stack trace — generous enough to
  /// keep real value (a truncated trace still shows where the failure
  /// originated) while keeping a single pathological event from
  /// growing the log unreasonably.
  static const _maxStackTraceChars = 4000;

  /// Null until [attachStore] runs (during bootstrap, right after the
  /// local database opens) — anything captured before that point still
  /// goes to [_fallbackStore] rather than being lost, which is exactly
  /// why startup/initialization failures (brief boundary list, Section
  /// 2) are genuinely covered and not just an aspiration.
  DiagnosticStore? _primaryStore;

  /// Called once during bootstrap, after the local database is open.
  /// Also opportunistically drains anything [_fallbackStore]
  /// accumulated before this point or during a transient primary-store
  /// failure.
  void attachStore(DiagnosticStore store) {
    _primaryStore = store;
    unawaited(_drainFallback());
  }

  /// Called once during bootstrap, in parallel with opening the
  /// database — resolves app version/device/OS info for
  /// [DeviceContext]. Never awaited by anything on the critical startup
  /// path; see DeviceContextProvider's own header comment.
  Future<void> resolveDeviceContext() => _deviceContextProvider.resolve();

  // ---------------------------------------------------------------
  // Breadcrumbs
  // ---------------------------------------------------------------

  /// Records one meaningful application event — "Product added to
  /// cart", "Sale transaction started". See BreadcrumbTrail's own
  /// header comment for what belongs here versus what doesn't.
  void breadcrumb(String message, {DiagnosticCategory? category, Map<String, String>? data}) {
    try {
      final redactedData = data == null ? null : _redactor.redactMap(data);
      _breadcrumbTrail.add(
        _redactor.redactText(message),
        category: category?.label,
        data: redactedData,
      );
    } catch (_) {
      // A breadcrumb is enrichment for whatever gets captured next, not
      // itself a failure worth surfacing.
    }
  }

  // ---------------------------------------------------------------
  // Multi-step operations ("Complete Sale" and similar)
  // ---------------------------------------------------------------

  /// Begins tracking a multi-step business operation — see
  /// [DiagnosticOperation]'s own header comment. `stages` is the full,
  /// known-in-advance step list (e.g. `['Validate cart', 'Create sale',
  /// ...]`) used only to number whichever stage is active if it fails
  /// ("Failure stage: 5 — Update inventory"); calling
  /// [DiagnosticOperation.stage] with a name not in this list still
  /// works, it just isn't numbered.
  DiagnosticOperation startOperation({
    required String operation,
    required String component,
    required DiagnosticCategory category,
    String? screen,
    List<String> stages = const [],
    Map<String, String>? context,
  }) {
    breadcrumb('$operation started', category: category, data: {'component': component});
    return DiagnosticOperation._(
      logger: this,
      operation: operation,
      component: component,
      category: category,
      screen: screen,
      stages: stages,
      initialContext: context ?? const {},
    );
  }

  // ---------------------------------------------------------------
  // Direct capture
  // ---------------------------------------------------------------

  /// Builds, redacts, and persists one [DiagnosticEvent]. Never throws —
  /// on any internal failure, returns a minimal in-memory-only event
  /// instead (see this class's own header comment on why).
  ///
  /// Not awaited by most call sites — see diagnostic_logger.dart's own
  /// header comment. A call site that has just caught an exception and
  /// needs to rethrow it should do `unawaited(logger.captureError(...));
  /// rethrow;`, not block the user-facing error path on disk I/O.
  Future<DiagnosticEvent> captureError({
    required Object error,
    required StackTrace stackTrace,
    required DiagnosticSeverity severity,
    required DiagnosticCategory category,
    String? component,
    String? operation,
    String? screen,
    String? failureStage,
    String? title,
    Map<String, String>? context,
    Map<String, String>? technicalContext,
    bool? isOffline,
  }) async {
    try {
      final signal = DiagnosticSignal(
        error: error,
        stackTrace: stackTrace,
        categoryHint: category,
        component: component,
        operation: operation,
        failureStage: failureStage,
        context: context,
        isOffline: isOffline,
      );
      final classification = _rootCauseEngine.classify(signal);
      final resolvedSeverity = classification.severityOverride ?? severity;

      final event = DiagnosticEvent(
        id: Ulid().toString(),
        severity: resolvedSeverity,
        category: category,
        title: title ?? _defaultTitleFor(category),
        message: _shortMessageFor(error),
        component: component,
        operation: operation,
        screen: screen,
        exceptionType: error.runtimeType.toString(),
        errorCode: _extractErrorCode(error),
        stackTrace: _truncateStackTrace(stackTrace.toString()),
        cause: classification.cause,
        evidence: classification.evidence,
        technicalContext: technicalContext?.entries.map((e) => EvidenceItem(e.key, e.value)).toList(),
        breadcrumbs: _breadcrumbTrail.snapshot(),
        failureStage: failureStage,
        device: _deviceContextProvider.current,
      );

      final redacted = _redactor.redactEvent(event);
      await _persist(redacted);
      return redacted;
    } catch (loggingError) {
      _lastResortPrint('failed to capture a diagnostic event: $loggingError');
      return DiagnosticEvent(
        id: 'capture-failed-${DateTime.now().microsecondsSinceEpoch}',
        severity: severity,
        category: category,
        title: title ?? _defaultTitleFor(category),
        message: 'This event could not be fully recorded.',
      );
    }
  }

  Future<void> _persist(DiagnosticEvent event) async {
    final store = _primaryStore;
    if (store != null) {
      final saved = await store.save(event);
      if (saved) return;
    }
    // Primary store is either not attached yet or just failed to write
    // (see FallbackDiagnosticStore's own header comment on exactly why
    // that second case matters) — either way, the event must not be
    // lost.
    final bufferedOk = await _fallbackStore.append(event);
    if (!bufferedOk) {
      _lastResortPrint('could not persist diagnostic event "${event.title}" anywhere');
    }
  }

  Future<void> _drainFallback() async {
    final store = _primaryStore;
    if (store == null) return;
    try {
      if (!await _fallbackStore.hasPendingEntries) return;
      final pending = await _fallbackStore.drainAll();
      for (final event in pending) {
        await store.save(event);
      }
    } catch (_) {
      // A failed drain leaves entries in the fallback file to retry
      // next time — nothing here is lost, just delayed.
    }
  }

  void _lastResortPrint(String message) {
    // The one line in this entire system that isn't itself wrapped in
    // another layer of defense — by the time execution reaches here,
    // both the primary store and the file-based fallback have already
    // failed, so there is genuinely nothing further to fall back to.
    // ignore: avoid_print
    print('[Fulus Diagnostics] $message');
  }

  // ---------------------------------------------------------------
  // Read access — the Diagnostics screen depends on DiagnosticLogger
  // alone rather than also needing a DiagnosticStore reference of its
  // own; these simply delegate, defaulting to empty/safe results before
  // attachStore() has run.
  // ---------------------------------------------------------------

  Stream<List<DiagnosticEvent>> watchEvents({DiagnosticFilter filter = const DiagnosticFilter(), int limit = 200}) {
    final store = _primaryStore;
    if (store == null) return Stream.value(const []);
    return store.watchEvents(filter: filter, limit: limit);
  }

  Future<DiagnosticEvent?> getById(String id) async => _primaryStore?.getById(id);

  Future<DiagnosticSummary> getSummary() async =>
      _primaryStore?.getSummary() ?? const DiagnosticSummary.empty();

  Future<void> markViewed(String id) async => _primaryStore?.markViewed(id);

  Future<List<DiagnosticEvent>> getForExport({DiagnosticFilter filter = const DiagnosticFilter()}) async =>
      _primaryStore?.getForExport(filter: filter) ?? const [];

  Future<void> applyRetentionPolicy({
    Duration olderThan = const Duration(days: 30),
    int keepAtLeast = 500,
  }) async {
    await _primaryStore?.applyRetentionPolicy(olderThan: olderThan, keepAtLeast: keepAtLeast);
  }

  Future<void> deleteAll() async => _primaryStore?.deleteAll();

  // ---------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------

  String _shortMessageFor(Object error) {
    if (error is Failure) return error.message;
    final text = error.toString().split('\n').first.trim();
    return text.length <= 140 ? text : '${text.substring(0, 137)}...';
  }

  String? _extractErrorCode(Object error) {
    if (error is DioException) return error.response?.statusCode?.toString();
    return null;
  }

  String _truncateStackTrace(String raw) {
    if (raw.length <= _maxStackTraceChars) return raw;
    final omitted = raw.length - _maxStackTraceChars;
    return '${raw.substring(0, _maxStackTraceChars)}\n... [truncated, $omitted more characters]';
  }

  String _defaultTitleFor(DiagnosticCategory category) {
    switch (category) {
      case DiagnosticCategory.sales:
        return 'Sale failed';
      case DiagnosticCategory.inventory:
        return 'Inventory update failed';
      case DiagnosticCategory.database:
        return 'A local operation failed';
      case DiagnosticCategory.network:
        return 'A network request failed';
      case DiagnosticCategory.authentication:
        return 'Sign-in problem';
      case DiagnosticCategory.synchronization:
        return 'Sync failed';
      case DiagnosticCategory.fileSystem:
        return 'File operation failed';
      case DiagnosticCategory.exportReporting:
        return 'Export failed';
      case DiagnosticCategory.platformChannel:
        return 'Device connection problem';
      case DiagnosticCategory.navigation:
        return "Couldn't open that screen";
      case DiagnosticCategory.validation:
        return 'Some information needs fixing';
      case DiagnosticCategory.stateConsistency:
        return "Something didn't match";
      case DiagnosticCategory.configuration:
        return 'Configuration problem';
      case DiagnosticCategory.startup:
        return 'Fulus failed to start';
      case DiagnosticCategory.flutterFramework:
        return 'Display error';
      case DiagnosticCategory.dartRuntime:
        return 'Unexpected error';
      case DiagnosticCategory.unknown:
        return 'Something went wrong';
    }
  }
}

/// Tracks one in-progress multi-step business operation — the
/// "Complete Sale" concept from the diagnostic-system brief's own
/// Section 5, generalized to any repository/service method with
/// identifiable stages. Created via [DiagnosticLogger.startOperation],
/// used like:
///
/// ```dart
/// final op = logger.startOperation(
///   operation: 'completeSale',
///   component: 'DraftCartRepositoryImpl',
///   category: DiagnosticCategory.sales,
///   stages: ['Validate cart', 'Build sale', 'Persist sale', 'Clear cart'],
/// );
/// op.stage('Validate cart');
/// ...
/// op.stage('Persist sale');
/// try {
///   await doTheWrite();
/// } catch (e, st) {
///   unawaited(op.fail(e, st, evidence: {'Sale ID': saleId}));
///   rethrow;
/// }
/// op.complete();
/// ```
///
/// Each [stage] call is a breadcrumb, not a nested operation of its
/// own — this is deliberate: it means a *sub*-step several layers
/// deeper (e.g. SaleRepositoryImpl's own internal steps inside the
/// single call this operation treats as its "Persist sale" stage) can
/// contribute its own finer-grained breadcrumbs without this class
/// needing to be threaded across a repository boundary. Whichever
/// [fail] eventually fires still captures the *complete* breadcrumb
/// trail, fine-grained sub-steps included, because breadcrumbs are one
/// shared, ambient trail (BreadcrumbTrail), not scoped per-operation —
/// see the implementation report for how this plays out concretely in
/// the completeSale flow.
class DiagnosticOperation {
  DiagnosticOperation._({
    required this.logger,
    required this.operation,
    required this.component,
    required this.category,
    required this.screen,
    required List<String> stages,
    required Map<String, String> initialContext,
  })  : _stages = stages,
        _context = Map.of(initialContext);

  final DiagnosticLogger logger;
  final String operation;
  final String component;
  final DiagnosticCategory category;
  final String? screen;
  final List<String> _stages;
  final Map<String, String> _context;

  String? _formattedStage;

  /// Marks [name] as the current stage — records a breadcrumb
  /// immediately, and remembers a numbered label ("3 — Create sale")
  /// for [fail] to attach as `failureStage`, when [name] matches one of
  /// the `stages` this operation was started with.
  void stage(String name) {
    final index = _stages.indexOf(name);
    _formattedStage = index == -1 ? name : '${index + 1} — $name';
    logger.breadcrumb('$operation: $name', category: category);
  }

  /// Adds to the evidence this operation will report if it later fails
  /// — e.g. `op.addContext({'Sale ID': saleId})` as soon as the ID is
  /// known, well before any failure is even possible.
  void addContext(Map<String, String> data) => _context.addAll(data);

  /// Captures a [DiagnosticEvent] for this operation's failure — see
  /// [DiagnosticLogger.captureError] for the general contract. Does
  /// **not** rethrow [error]; the caller remains responsible for that,
  /// exactly as if this call weren't here at all, so adding
  /// instrumentation to an existing method never changes its own error
  /// contract with its callers.
  Future<DiagnosticEvent> fail(
    Object error,
    StackTrace stackTrace, {
    DiagnosticSeverity severity = DiagnosticSeverity.error,
    Map<String, String>? evidence,
    Map<String, String>? technicalContext,
    String? title,
  }) {
    return logger.captureError(
      error: error,
      stackTrace: stackTrace,
      severity: severity,
      category: category,
      component: component,
      operation: operation,
      screen: screen,
      failureStage: _formattedStage,
      title: title,
      context: {..._context, ...?evidence},
      technicalContext: technicalContext,
    );
  }

  /// Optional — a breadcrumb marking clean completion, useful mainly so
  /// "Recent activity" on a *later, unrelated* failure can show this
  /// operation finished normally rather than leaving its last-seen
  /// state ambiguous.
  void complete() {
    logger.breadcrumb('$operation completed', category: category);
  }
}
