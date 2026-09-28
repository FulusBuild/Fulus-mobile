import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/sync/sync_status.dart';

void main() {
  test('pending queue is not reported as up to date even after previous syncs', () {
    final health = SyncHealthSnapshot(
      lastPushAt: DateTime(2026, 9, 28, 12),
      lastPullAt: DateTime(2026, 9, 28, 12, 1),
    );

    expect(
      cloudBackupLabel(health, SyncStatusKind.pending),
      'Backup pending',
    );
    expect(
      cloudBackupLabel(health, SyncStatusKind.attentionNeeded),
      'Needs attention',
    );
  });

  test('settled status can report up to date after successful sync history', () {
    final health = SyncHealthSnapshot(
      lastPushAt: DateTime(2026, 9, 28, 12),
      lastPullAt: DateTime(2026, 9, 28, 12, 1),
    );

    expect(
      cloudBackupLabel(health, SyncStatusKind.settled),
      'Up to date',
    );
  });

  test('settled status without successful history waits for first backup', () {
    expect(
      cloudBackupLabel(const SyncHealthSnapshot(), SyncStatusKind.settled),
      'Waiting for first backup',
    );
  });
}
