import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fulus_mobile/sync/sync_cycle_execution_gate.dart';

void main() {
  test('coalesces concurrent cycles', () async {
    final release = Completer<void>();
    var runs = 0;
    final gate = SyncCycleExecutionGate(
      runCycle: ({manual = false}) async {
        runs++;
        await release.future;
        return true;
      },
      runFollowUp: () async => true,
      isActive: () => true,
      onFollowUpError: (_, __) {},
    );

    final first = gate.run();
    final second = gate.run();

    expect(gate.isRunning, isTrue);
    release.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(runs, 1);
  });

  test('coalesces mutation notifications into one follow-up', () async {
    final release = Completer<void>();
    final followUpStarted = Completer<void>();
    final releaseFollowUp = Completer<void>();
    var cycles = 0;
    var followUps = 0;

    final gate = SyncCycleExecutionGate(
      runCycle: ({manual = false}) async {
        cycles++;
        await release.future;
        return true;
      },
      runFollowUp: () async {
        followUps++;
        followUpStarted.complete();
        await releaseFollowUp.future;
        return true;
      },
      isActive: () => true,
      onFollowUpError: (_, __) {},
    );

    final cycle = gate.run();
    gate.requestAfterCurrentCycle();
    gate.requestAfterCurrentCycle();
    release.complete();

    await cycle;
    await followUpStarted.future;

    expect(cycles, 1);
    expect(followUps, 1);

    final idle = gate.waitForIdle();
    var idleCompleted = false;
    unawaited(idle.then((_) => idleCompleted = true));
    await Future<void>.delayed(Duration.zero);
    expect(idleCompleted, isFalse);

    releaseFollowUp.complete();
    await idle;
  });

  test('clears cycle state after a failed cycle', () async {
    final gate = SyncCycleExecutionGate(
      runCycle: ({manual = false}) async {
        throw StateError('cycle failed');
      },
      runFollowUp: () async => true,
      isActive: () => true,
      onFollowUpError: (_, __) {},
    );

    await expectLater(gate.run(), throwsStateError);
    expect(gate.isRunning, isFalse);
  });

  test('does not schedule a follow-up when runtime is inactive', () async {
    var followUps = 0;
    final gate = SyncCycleExecutionGate(
      runCycle: ({manual = false}) async => true,
      runFollowUp: () async {
        followUps++;
        return true;
      },
      isActive: () => false,
      onFollowUpError: (_, __) {},
    );

    final cycle = gate.run();
    gate.requestAfterCurrentCycle();
    await cycle;
    await Future<void>.delayed(Duration.zero);

    expect(followUps, 0);
  });
}
