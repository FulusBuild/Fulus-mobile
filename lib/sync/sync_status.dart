import 'package:equatable/equatable.dart';

/// Internal sync state. The UI deliberately exposes only reassuring,
/// actionable information; queue counts remain an implementation detail.
enum SyncStatusKind {
  disabled,
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

  const SyncStatus.settled() : this._(kind: SyncStatusKind.settled);

  /// The queue count is intentionally not exposed to normal UI. A pending
  /// state simply means Fulus has saved work locally and will continue
  /// automatically; users do not need to monitor a queue.
  const SyncStatus.pending(int count)
      : this._(kind: SyncStatusKind.pending);

  const SyncStatus.syncing(int pendingCount)
      : this._(kind: SyncStatusKind.syncing);

  const SyncStatus.attentionNeeded({
    required int attentionCount,
    required int pendingCount,
  }) : this._(
          kind: SyncStatusKind.attentionNeeded,
          attentionCount: attentionCount,
        );

  final SyncStatusKind kind;

  /// Kept for compatibility with existing internal callers. Normal UI
  /// should not use queue size as a progress metric.
  final int pendingCount;

  final int attentionCount;

  @override
  List<Object?> get props => [kind, pendingCount, attentionCount];
}
