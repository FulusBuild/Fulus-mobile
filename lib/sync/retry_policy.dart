/// **Phase 0 completion pass.** Named in the Architecture doc's Section
/// 1 folder structure and explicitly flagged in this project's own
/// history as a deliberate, real gap — every prior stage left this
/// unbuilt on purpose rather than by oversight. Closing it now.
///
/// Pure Dart, no dependency on SyncEngine or the database — same
/// isolation this codebase already holds sync_engine.dart itself to
/// (see that file's own header comment). Answers exactly one question:
/// given how many times a queued item has already failed and when it
/// last tried, has enough time passed to try it again?
///
/// Exponential backoff with a cap, not unbounded exponential growth —
/// SyncEngine's [maxAttemptsBeforeAttentionNeeded] already provides the
/// upper bound on ATTEMPT COUNT (an item stops being retried at all
/// past that); this provides the upper bound on DELAY BETWEEN attempts,
/// so a shop with patchy connectivity doesn't end up waiting literally
/// hours between the 4th and 5th attempt just because 2^4 kept
/// doubling unchecked.
class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 30),
  });

  /// Delay after the very first failure. 30 seconds chosen the same way
  /// SyncEngine's own `maxAttemptsBeforeAttentionNeeded = 5` was — "a
  /// reasonable default for a foundation phase," not a figure specified
  /// anywhere in the Architecture doc, which names the *shape*
  /// (exponential, capped) without naming exact numbers.
  final Duration baseDelay;

  /// Upper bound on the computed delay, regardless of how many attempts
  /// have accumulated — 30 minutes chosen so a device that comes back
  /// online mid-morning after a bad-connectivity night is never more
  /// than half an hour from its next real attempt, while still backing
  /// off enough that a genuinely dead server isn't hammered every 30
  /// seconds for hours.
  final Duration maxDelay;

  /// [syncAttempts] is the count already recorded on the queue item
  /// (SyncQueueItems.syncAttempts) — 0 before any attempt has ever been
  /// made. Doubles per attempt: 30s, 1m, 2m, 4m, 8m, ... capped at
  /// [maxDelay]. The `clamp` guards against a pathologically large
  /// exponent overflowing `1 <<` for an item that's somehow accumulated
  /// an enormous attempt count — shouldn't happen given
  /// maxAttemptsBeforeAttentionNeeded caps attempts well below this, but
  /// costs nothing to guard against directly rather than trust that
  /// invariant transitively.
  Duration backoffFor(int syncAttempts) {
    final exponent = syncAttempts.clamp(0, 20);
    final delay = baseDelay * (1 << exponent);
    return delay > maxDelay ? maxDelay : delay;
  }

  /// [lastAttemptedAt] null means this item has never actually been
  /// attempted yet (freshly enqueued) — always eligible immediately,
  /// same as [syncAttempts] being 0. Otherwise: has [backoffFor] this
  /// item's own current attempt count elapsed since [lastAttemptedAt],
  /// as of [now]?
  bool isEligibleForRetry({
    required int syncAttempts,
    required DateTime? lastAttemptedAt,
    required DateTime now,
  }) {
    if (lastAttemptedAt == null || syncAttempts <= 0) return true;
    final readyAt = lastAttemptedAt.add(backoffFor(syncAttempts));
    return !now.isBefore(readyAt);
  }
}
