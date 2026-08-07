import 'package:equatable/equatable.dart';

/// The sync indicator's state, per Volume 12 ("The Sync Indicator, Fully
/// Specified"): "exactly four visual states: quiet/settled (fully
/// synced), a small count (items pending), actively spinning (syncing
/// right now), and a soft amber mark (something needs attention)."
///
/// [disabled] is a fifth state the Bible's Volume 12 never needed to
/// specify, because it was written assuming sync always exists — Stage
/// 16 is precisely what makes it possible for sync not to. A future
/// Settings screen reading this needs to tell "nothing pending because
/// everything's synced" apart from "nothing pending because the sync
/// extension isn't switched on" — collapsing those into one state would
/// silently misrepresent the second as the first.
enum SyncStatusKind {
  /// The extension is off (SyncConfig.isEnabled == false). No
  /// SyncQueueItems row will ever be drained while this holds — they
  /// still accumulate locally (see sync_queue.dart), just untouched.
  disabled,

  /// Enabled, and every queued item has been confirmed synced. The
  /// Bible's own "settled."
  settled,

  /// Enabled, with `count` items waiting to be sent — offline, or
  /// simply not yet reached by the drain loop.
  pending,

  /// Enabled, and a drain is actively in progress right now. Per the
  /// Bible, "a brief, transient state, not one the user needs to wait
  /// on."
  syncing,

  /// Enabled, and at least one item has crossed
  /// SyncEngine.maxAttemptsBeforeAttentionNeeded — the Bible's "stuck
  /// sync" case, and the trigger for Volume 12 Decision 43's second
  /// notification (see sync_status_notifier.dart).
  attentionNeeded,
}

class SyncStatus extends Equatable {
  const SyncStatus._({
    required this.kind,
    this.pendingCount = 0,
    this.attentionCount = 0,
  });

  const SyncStatus.disabled() : this._(kind: SyncStatusKind.disabled);

  const SyncStatus.settled() : this._(kind: SyncStatusKind.settled);

  const SyncStatus.pending(int count)
      : this._(kind: SyncStatusKind.pending, pendingCount: count);

  const SyncStatus.syncing(int pendingCount)
      : this._(kind: SyncStatusKind.syncing, pendingCount: pendingCount);

  const SyncStatus.attentionNeeded({
    required int attentionCount,
    required int pendingCount,
  }) : this._(
          kind: SyncStatusKind.attentionNeeded,
          attentionCount: attentionCount,
          pendingCount: pendingCount,
        );

  final SyncStatusKind kind;

  /// Items in SyncQueueItems not yet confirmed synced — meaningful for
  /// [SyncStatusKind.pending] and [SyncStatusKind.syncing]; zero
  /// otherwise (including for [SyncStatusKind.attentionNeeded], where
  /// [attentionCount] is the number that actually matters).
  final int pendingCount;

  /// Items that have crossed the attention threshold specifically —
  /// only meaningful for [SyncStatusKind.attentionNeeded].
  final int attentionCount;

  @override
  List<Object?> get props => [kind, pendingCount, attentionCount];
}
