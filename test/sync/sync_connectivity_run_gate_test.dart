import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/sync/sync_connectivity_run_gate.dart';

void main() {
  test('coalesces concurrent connectivity runs', () async {
    final gateCompleter = Future<void>.delayed(Duration.zero);
    var runs = 0;
    final gate = SyncConnectivityRunGate(run: () async {
      runs++;
      await gateCompleter;
      return true;
    });

    final first = gate.run();
    final second = gate.run();

    expect(gate.isRunning, isTrue);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(runs, 1);
    expect(gate.isRunning, isFalse);
  });

  test('coalesces synchronous re-entry before the callback first awaits', () async {
    late SyncConnectivityRunGate gate;
    var runs = 0;
    gate = SyncConnectivityRunGate(run: () async {
      runs++;
      if (runs == 1) {
        await gate.run();
      }
      return true;
    });

    expect(await gate.run(), isTrue);
    expect(runs, 1);
  });

  test('clears running state when the attempt fails', () async {
    final gate = SyncConnectivityRunGate(run: () async {
      throw StateError('offline');
    });

    await expectLater(gate.run(), throwsStateError);
    expect(gate.isRunning, isFalse);
  });
}
