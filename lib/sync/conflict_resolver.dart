/// **Phase 0 completion pass.** Named in the Architecture doc's Section
/// 1 folder structure and explicitly flagged in this project's own
/// history alongside RetryPolicy as a deliberate, real gap.
///
/// Scoped honestly, not ambitiously: this architecture has no
/// per-entity version number, ETag, or last-known-server-state to
/// compare against (see Sales/Products/every other syncable table's own
/// doc comments — SyncableColumns tracks *this device's* sync status,
/// not a comparable server-side version marker), so a genuine
/// field-by-field three-way merge isn't something this class can do
/// with the data actually available. What it CAN do, and does: notice
/// when a push failure's own message is describing a conflict rather
/// than an ordinary rejection, and make that visible as a distinct,
/// findable category instead of one more opaque "attention needed"
/// error string indistinguishable from a stock-validation failure or a
/// bad reference.
///
/// Resolution strategy is local-wins-by-default: a conflicting item
/// stays in the queue (SyncEngine still marks it attentionNeeded, same
/// as today) rather than being silently dropped or having the server's
/// version silently overwrite it — the person gets to make the real
/// choice once a screen exists to show them "this changed elsewhere,"
/// rather than this class guessing which side should win.
class ConflictResolver {
  const ConflictResolver();

  /// Deliberately conservative — matched against api_client.dart's own
  /// actual 409 message text ("This already happened — no changes
  /// needed." — though that specific one is intercepted as a SUCCESS
  /// signal before it ever reaches here, per SalesApi.createSale) and
  /// the general shape a "this record moved under you" backend message
  /// takes. A message this doesn't recognize is treated as an ordinary
  /// failure, not silently up-ranked into a conflict on a guess.
  static const _conflictMarkers = [
    'already exists',
    'already happened',
    'no longer exists',
    'has changed',
    'was modified',
    'conflict',
  ];

  /// True if [failureMessage] (a BusinessRuleFailure.message, at the
  /// one call site that uses this — see sync_engine.dart) reads like a
  /// genuine version conflict rather than some other business-rule
  /// rejection ("insufficient stock," "invalid category," and so on,
  /// neither of which mention any of [_conflictMarkers]).
  bool looksLikeConflict(String failureMessage) {
    final lower = failureMessage.toLowerCase();
    return _conflictMarkers.any(lower.contains);
  }

  /// Prefixes the stored error so it's a distinct, greppable category —
  /// SyncQueueItems.lastError stays a plain text column (no schema
  /// change for something this narrow in scope), but "[CONFLICT] ..."
  /// vs. a bare message is enough for a future sync-status screen to
  /// group by, the same lightweight convention this codebase already
  /// uses elsewhere for a marker inside a text field rather than a new
  /// column (Sale.notes' own "[CANCELLED ...]" prefix, read by
  /// ReceiptRepositoryImpl — same idea, applied here).
  String annotate(String failureMessage) => '[CONFLICT] $failureMessage';
}
