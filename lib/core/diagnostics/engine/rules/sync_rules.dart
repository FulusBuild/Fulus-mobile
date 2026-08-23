import '../../models/diagnostic_event.dart';
import '../diagnostic_rule.dart';
import '../diagnostic_signal.dart';

/// Sync-layer rules. [SyncVersionConflictRule] is matched on the exact
/// `[CONFLICT] ` prefix `ConflictResolver.annotate` (sync/conflict_resolver.dart)
/// already writes into `SyncQueueItems.lastError` — reusing that
/// existing, deliberate marker rather than re-deriving conflict
/// detection independently here, so the two can never disagree about
/// what counts as a conflict.
class SyncVersionConflictRule extends DiagnosticRule {
  const SyncVersionConflictRule();

  @override
  String get name => 'sync.versionConflict';

  @override
  bool matches(DiagnosticSignal signal) => signal.effectiveErrorText.contains('[CONFLICT]');

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This record was changed on another device (or the server) '
            'since this device last synced it, and the two versions now conflict. '
            'The local copy stays as-is and needs attention — see Sync in More.',
        confidence: DiagnosticConfidence.high,
      );
}

class SyncHandlerMissingRule extends DiagnosticRule {
  const SyncHandlerMissingRule();

  @override
  String get name => 'sync.handlerMissing';

  @override
  bool matches(DiagnosticSignal signal) =>
      signal.effectiveErrorText.contains('No sync handler registered');

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This item was queued for sync with a record type Fulus has '
            'no sync handler for — a real gap in how the item was enqueued, not a '
            'transient failure. Retrying will not fix this on its own.',
        confidence: DiagnosticConfidence.high,
      );
}

/// The threshold case — an item that has failed repeatedly and is now
/// flagged `attentionNeeded` (sync_engine.dart's own
/// `maxAttemptsBeforeAttentionNeeded`) for a reason that didn't match
/// either specific rule above: a genuinely transient failure (server
/// unreachable, timing out) that simply never stopped happening long
/// enough to succeed.
class SyncAttentionThresholdRule extends DiagnosticRule {
  const SyncAttentionThresholdRule();

  @override
  String get name => 'sync.attentionThreshold';

  @override
  bool matches(DiagnosticSignal signal) => signal.context['syncOutcome'] == 'attentionNeeded';

  @override
  DiagnosticCause apply(DiagnosticSignal signal) => const DiagnosticCause(
        description: 'This item failed to sync repeatedly and has stopped being '
            'retried automatically. See the technical details for the specific '
            'error from the most recent attempt.',
        confidence: DiagnosticConfidence.medium,
      );
}

const List<DiagnosticRule> syncRules = [
  SyncVersionConflictRule(),
  SyncHandlerMissingRule(),
  SyncAttentionThresholdRule(),
];
