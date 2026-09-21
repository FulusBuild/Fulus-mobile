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
  }) : this._(
          kind: SyncStatusKind.attentionNeeded,
          attentionCount: attentionCount,
          pendingCount: pendingCount,
        );

  final SyncStatusKind kind;

  /// Number of queued writes still waiting for cloud backup.
  final int pendingCount;

  /// Number of queued writes that have exhausted automatic retry attempts.
  final int attentionCount;

  @override
  List<Object?> get props => [kind, pendingCount, attentionCount];
}
