import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/sync/sync_restore_reconciliation_gate.dart';

void main() {
  test('restore gate blocks readiness while reconciliation is active', () async {
    final gate = SyncRestoreReconciliationGate();
    gate.begin();
    expect(gate.isInProgress, isTrue);

    var reconciled = false;
    final run = gate.run(() async {
      expect(gate.isInProgress, isTrue);
      reconciled = true;
    });

    await run;

    expect(reconciled, isTrue);
    expect(gate.isInProgress, isFalse);
    expect(gate.activeRun, isNull);
  });

  test('cancel releases an armed restore gate before reconciliation starts', () {
    final gate = SyncRestoreReconciliationGate();
    gate.begin();
    expect(gate.isInProgress, isTrue);

    gate.cancel();

    expect(gate.isInProgress, isFalse);
  });

  test('concurrent restore reconciliation shares one run', () async {
    final gate = SyncRestoreReconciliationGate();
    gate.begin();
    var runs = 0;
    final first = gate.run(() async {
      runs++;
      await Future<void>.delayed(Duration.zero);
    });
    final second = gate.run(() async {
      runs++;
    });

    await Future.wait([first, second]);

    expect(runs, 1);
    expect(gate.isInProgress, isFalse);
  });
}
