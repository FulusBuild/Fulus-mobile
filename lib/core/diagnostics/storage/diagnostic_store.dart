import '../models/diagnostic_event.dart';

/// What [DiagnosticLogger] needs from a persistence backend — enough to
/// swap the primary Drift-backed store (storage/drift_diagnostic_store.dart)
/// for the emergency file-based one (storage/fallback_diagnostic_store.dart)
/// without either the logger or the Diagnostics screen needing to know
/// which is currently in use.
///
/// Every method here is expected to be internally defensive (catch its
/// own storage-layer exceptions rather than let them escape) — see
/// diagnostic_logger.dart's own header comment on why: a diagnostic
/// system whose own storage call can crash the app it's meant to be
/// diagnosing has failed at its one non-negotiable job. `save` returning
/// `false` instead of throwing is how a failed write is communicated
/// back to the logger, which is what actually decides to fall back to
/// the emergency store.
abstract class DiagnosticStore {
  /// Persists [event]. Returns `true` on success, `false` if the write
  /// failed for any reason — never throws.
  Future<bool> save(DiagnosticEvent event);

  /// Ordered newest-first, matching filters "AND"ed together. `limit`
  /// bounds how many rows are fetched at once (the list screen pages
  /// through this, not filters it further client-side) —
  /// see storage/drift_diagnostic_store.dart's own query for exactly
  /// which columns each filter maps onto.
  Stream<List<DiagnosticEvent>> watchEvents({DiagnosticFilter filter = const DiagnosticFilter(), int limit = 200});

  Future<DiagnosticEvent?> getById(String id);

  Future<DiagnosticSummary> getSummary();

  /// Marks [id] as [DiagnosticLifecycleStatus.viewed] — called once,
  /// the first time the detail screen opens a given event; a no-op if
  /// the id doesn't exist (defensive, never throws).
  Future<void> markViewed(String id);

  /// Every event matching [filter], unpaginated — used only by the
  /// share/export flow (a bounded, user-initiated action), never by the
  /// list screen's own ordinary display path.
  Future<List<DiagnosticEvent>> getForExport({DiagnosticFilter filter = const DiagnosticFilter()});

  /// Retention/cleanup (brief Section 14): deletes events older than
  /// [olderThan] beyond the most recent [keepAtLeast], whichever is more
  /// conservative — see the Drift implementation's own doc comment for
  /// why both bounds exist together rather than just one.
  Future<void> applyRetentionPolicy({required Duration olderThan, required int keepAtLeast});

  Future<void> deleteAll();
}
