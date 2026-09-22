import 'package:equatable/equatable.dart';

/// Internal sync state. The UI deliberately exposes only reassuring,
/// actionable information; queue counts remain an implementation detail.
enum SyncStatusKind {
  disabled,
  cloudUnavailable,
  settled,
  pending,
  syncing,
  attentionNeeded,
}

class SyncStatus extends Equatable {
  const SyncStatus._({
    required this.kind,
    this.pendingCount = 0,
    this.attentionCount = 0,
    this.conflictCount = 0,
  });

  const SyncStatus.disabled() : this._(kind: SyncStatusKind.disabled);

  const SyncStatus.cloudUnavailable()
      : this._(kind: SyncStatusKind.cloudUnavailable);

  const SyncStatus.settled() : this._(kind: SyncStatusKind.settled);

  const SyncStatus.pending(int count)
      : this._(kind: SyncStatusKind.pending, pendingCount: count);

  const SyncStatus.syncing(int pendingCount)
      : this._(
          kind: SyncStatusKind.syncing,
          pendingCount: pendingCount,
        );

  const SyncStatus.attentionNeeded({
    required int attentionCount,
    required int pendingCount,
    int conflictCount = 0,
  })  : kind = SyncStatusKind.attentionNeeded,
        pendingCount = pendingCount,
        attentionCount = attentionCount,
        conflictCount = conflictCount;

  final SyncStatusKind kind;

  /// Number of queued writes still waiting for cloud backup.
  final int pendingCount;

  /// Number of queued writes that have exhausted automatic retry attempts.
  final int attentionCount;

  /// Number of unresolved optimistic-concurrency conflicts retained locally.
  final int conflictCount;

  @override
  List<Object?> get props => [kind, pendingCount, attentionCount, conflictCount];
}


class SyncHealthSnapshot extends Equatable {
  const SyncHealthSnapshot({
    this.lastPushAt,
    this.lastPullAt,
    this.cursor = 0,
    this.recoveryState = 'idle',
    this.lastError,
  });

  final DateTime? lastPushAt;
  final DateTime? lastPullAt;
  final int cursor;
  final String recoveryState;
  final String? lastError;

  @override
  List<Object?> get props => [lastPushAt, lastPullAt, cursor, recoveryState, lastError];
}
