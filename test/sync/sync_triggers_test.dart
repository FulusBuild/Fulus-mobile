import 'dart:async';

import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSyncEngine extends Mock implements SyncEngine {}
class MockConnectivity extends Mock implements Connectivity {}
class MockSyncStatusNotifier extends Mock implements SyncStatusNotifier {}
class MockSyncExecutionLease extends Mock implements SyncExecutionLease {}

void main() {
  late MockSyncEngine syncEngine;
  late MockConnectivity connectivity;
  late MockSyncStatusNotifier syncStatusNotifier;
  late MockSyncExecutionLease executionLease;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    syncEngine = MockSyncEngine();
    connectivity = MockConnectivity();
    syncStatusNotifier = MockSyncStatusNotifier();
    executionLease = MockSyncExecutionLease();
    when(() => executionLease.acquire()).thenAnswer((_) async => true);
    when(() => executionLease.release()).thenAnswer((_) async {});
    when(() => syncStatusNotifier.checkForStuckSyncAndNotify())
        .thenAnswer((_) async {});
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream.empty());
  });

  group('sync disabled', () {
    test('start() never checks connectivity and never runs the engine', () async {
      final config = await SyncConfig.load();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        executionLease: executionLease,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.start();
      verifyNever(() => connectivity.checkConnectivity());
      verifyNever(() => syncEngine.runOnce(manual: any(named: 'manual')));
    });

    test('notifyEnqueued() is a silent no-op', () async {
      final config = await SyncConfig.load();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.notifyEnqueued();
      verifyNever(() => connectivity.checkConnectivity());
    });

    test('syncNow() throws instead of silently reaching the network', () async {
      final config = await SyncConfig.load();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await expectLater(triggers.syncNow(), throwsStateError);
      verifyNever(() => syncEngine.runOnce(manual: any(named: 'manual')));
    });

    test('didChangeAppLifecycleState(resumed) does not trigger a run', () async {
      final config = await SyncConfig.load();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      triggers.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => connectivity.checkConnectivity());
    });
  });

  group('runtime toggle', () {
    test('enabling sync after start activates triggers immediately', () async {
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.start();
      await config.setEnabled(true);
      await untilCalled(() => syncEngine.runOnce(manual: any(named: 'manual')));
      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
    });

    test('disabling sync after start stops connectivity listening', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.start();
      await config.setEnabled(false);
      await triggers.notifyEnqueued();
      verify(() => connectivity.checkConnectivity()).called(1);
    });
  });

  group('sync enabled', () {
    test('periodic retry retries pending work without waiting for a connectivity event', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      var runCount = 0;
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
      });

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
        retryInterval: const Duration(milliseconds: 10),
      );

      await triggers.start();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(runCount, greaterThanOrEqualTo(2));
      triggers.dispose();
    });

    test('periodic retry survives a failed cycle and continues syncing', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());

      var runCount = 0;
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount == 1) {
          throw StateError('temporary cloud failure');
        }
      });

      Object? reportedError;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
        retryInterval: const Duration(milliseconds: 10),
        onSyncFailure: (error, _) => reportedError = error,
      );

      await expectLater(triggers.start(), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 55));

      expect(runCount, greaterThanOrEqualTo(3));
      expect(reportedError, isA<StateError>());
      triggers.dispose();
    });

    test('periodic retry survives repeated transient failures across 100 cycles', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());

      var runCount = 0;
      var failureCount = 0;
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount <= 25) {
          throw StateError('temporary cloud failure $runCount');
        }
      });

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
        retryInterval: const Duration(milliseconds: 1),
        onSyncFailure: (error, _) => failureCount++,
      );

      await expectLater(triggers.start(), throwsStateError);

      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (runCount < 100 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(runCount, greaterThanOrEqualTo(100));
      expect(failureCount, greaterThanOrEqualTo(25));
      triggers.dispose();
    });

    test('network interruption resumes sync automatically when connectivity returns', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final connectivityChanges = StreamController<List<ConnectivityResult>>();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => connectivityChanges.stream);
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      var runCount = 0;
      final resumedRun = Completer<void>();
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount == 2 && !resumedRun.isCompleted) {
          resumedRun.complete();
        }
      });

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
        retryInterval: const Duration(hours: 1),
      );

      await triggers.start();
      expect(runCount, 1);

      connectivityChanges.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(runCount, 1);

      connectivityChanges.add([ConnectivityResult.wifi]);
      await resumedRun.future;

      expect(runCount, 2);
      verify(() => syncEngine.runOnce(manual: false)).called(2);

      triggers.dispose();
      await connectivityChanges.close();
    });

    test('resuming the app rechecks connectivity and triggers sync when enabled', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );

      var runCount = 0;
      final resumedRun = Completer<void>();
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount == 2 && !resumedRun.isCompleted) {
          resumedRun.complete();
        }
      });

      await triggers.start();
      expect(runCount, 1);

      triggers.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await resumedRun.future;

      verify(() => connectivity.checkConnectivity()).called(2);
      verify(() => syncEngine.runOnce(manual: false)).called(2);
      triggers.dispose();
    });

    test('start() checks connectivity and runs the engine when online', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.start();
      await untilCalled(() => syncEngine.runOnce(manual: any(named: 'manual')));
      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
    });

    test('syncNow() runs the engine and then checks for a stuck sync', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {});
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );
      await triggers.syncNow();
      verify(() => syncEngine.runOnce(manual: true)).called(1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
    });

    test('does not run until cloud readiness is true', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => false,
        connectivity: connectivity,
      );

      await triggers.start();
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => connectivity.checkConnectivity());
      verifyNever(() => syncEngine.runOnce(manual: any(named: 'manual')));
    });

    test('startup readiness initialization reconciles without a circular await', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});

      var ready = false;
      var initializationCalls = 0;
      late final SyncTriggers triggers;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => ready,
        onNotReady: () async {
          initializationCalls++;
          await triggers.reconcileForReadiness();
          ready = true;
        },
        connectivity: connectivity,
      );

      await expectLater(triggers.start(), completes);

      expect(initializationCalls, 1);
      expect(ready, isTrue);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
      triggers.dispose();
    });

    test('manual sync reports a clear readiness failure', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => false,
        connectivity: connectivity,
      );

      await expectLater(triggers.syncNow(), throwsA(isA<StateError>()));
      verifyNever(() => syncEngine.runOnce(manual: true));
    });

    test('manual sync can retry cloud readiness before syncing', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});

      var ready = false;
      late final SyncTriggers triggers;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => ready,
        onNotReady: () async {
          await triggers.reconcileForReadiness();
          ready = true;
        },
        connectivity: connectivity,
      );

      await triggers.syncNow();

      expect(ready, isTrue);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
      verifyNever(() => syncEngine.runOnce(manual: true));
      triggers.dispose();
    });

    test('restores Sync Ready only after stale-cursor recovery and pull succeed', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {});

      var pullCalls = 0;
      var recoveryCalls = 0;
      var ready = false;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => true,
        pullFromServer: () async {
          pullCalls++;
          if (pullCalls == 1) {
            throw const BusinessRuleFailure(
              'stale cursor',
              code: 'SYNC_CURSOR_TOO_OLD',
            );
          }
        },
        onCursorTooOldRecovery: () async {
          recoveryCalls++;
        },
        onRecoveryReconciled: () async {
          ready = true;
        },
      );

      await triggers.syncNow();

      expect(pullCalls, 2);
      expect(recoveryCalls, 1);
      expect(ready, isTrue);
      verify(() => syncEngine.runOnce(manual: true)).called(1);
    });

    test(
        'a mutation enqueued during a sync cycle triggers one follow-up cycle after pull',
        () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());

      final firstCycleStarted = Completer<void>();
      final releaseFirstCycle = Completer<void>();
      var runCount = 0;
      late final SyncTriggers triggers;
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount == 1) {
          firstCycleStarted.complete();
          // Let _runSyncCycle publish its active-cycle marker before modeling
          // SyncQueue's next-turn onEnqueued callback.
          await Future<void>.delayed(Duration.zero);
          // This models SyncQueue's next-turn onEnqueued callback while the
          // push/pull cycle is still active.
          await triggers.notifyEnqueued();
          await releaseFirstCycle.future;
        }
      });

      var pullCount = 0;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
        pullFromServer: () async {
          pullCount++;
        },
      );

      final firstRun = triggers.start();
      await firstCycleStarted.future;
      expect(runCount, 1);

      releaseFirstCycle.complete();
      await firstRun;

      for (var i = 0; i < 20 && runCount < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      expect(runCount, 2);
      expect(pullCount, 2);
      triggers.dispose();
    });

    test('waitForIdle blocks while a sync cycle is in flight', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final cycleStarted = Completer<void>();
      final releaseCycle = Completer<void>();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {
        cycleStarted.complete();
        await releaseCycle.future;
      });

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );

      final syncRun = triggers.syncNow();
      await cycleStarted.future;

      var idle = false;
      final idleRun = triggers.waitForIdle().then((_) => idle = true);
      await Future<void>.delayed(Duration.zero);
      expect(idle, isFalse);

      releaseCycle.complete();
      await Future.wait([syncRun, idleRun]);
      expect(idle, isTrue);
    });

    test('waitForIdle does not wait on readiness orchestration', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final readinessStarted = Completer<void>();
      final releaseReadiness = Completer<void>();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      late final SyncTriggers triggers;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => false,
        onNotReady: () async {
          readinessStarted.complete();
          await releaseReadiness.future;
        },
        connectivity: connectivity,
      );

      final startup = triggers.start();
      await readinessStarted.future;

      await expectLater(triggers.waitForIdle(), completes);

      releaseReadiness.complete();
      await startup;
      triggers.dispose();
    });


    test('device authorization recovery waits for the active cycle then re-enters readiness', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final cycleStarted = Completer<void>();
      final releaseCycle = Completer<void>();
      var runCount = 0;
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {
        runCount++;
        if (runCount == 1) {
          cycleStarted.complete();
          await releaseCycle.future;
        }
      });

      var ready = true;
      var readinessCalls = 0;
      late final SyncTriggers triggers;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => ready,
        onNotReady: () async {
          readinessCalls++;
          ready = true;
          // Bootstrap's real readiness initializer performs the first
          // reconciliation before advertising Sync Ready. Model that
          // contract here so recovery does not require a second trigger.
          await syncEngine.runOnce(manual: false);
        },
        connectivity: connectivity,
        retryInterval: const Duration(hours: 1),
      );

      final first = triggers.start();
      await cycleStarted.future;

      ready = false;
      triggers.scheduleReadinessRecovery();
      await Future<void>.delayed(Duration.zero);
      expect(runCount, 1);

      releaseCycle.complete();
      await first;
      // Recovery is deliberately scheduled through a 250ms lifecycle timer
      // so it cannot recursively await the active sync cycle. Wait for that
      // boundary rather than asserting immediately after the first cycle.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(readinessCalls, 1);
      expect(runCount, 2);
      triggers.dispose();
    });

    test('reports a successful cycle after push and pull both complete', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {});

      var successCalls = 0;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        onSyncSuccess: () => successCalls++,
        pullFromServer: () async {},
      );

      await triggers.syncNow();

      expect(successCalls, 1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
    });

    test('pull failure does not report a successful sync cycle', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {});

      Object? reportedError;
      var successCalls = 0;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        pullFromServer: () async => throw const BusinessRuleFailure(
          'pull blocked',
          code: 'SYNC_CONFLICT_PENDING',
        ),
        onSyncSuccess: () => successCalls++,
        onSyncFailure: (error, _) => reportedError = error,
      );

      await expectLater(triggers.syncNow(), throwsA(isA<BusinessRuleFailure>()));
      expect(reportedError, isA<BusinessRuleFailure>());
      expect(successCalls, 0);
      verify(() => syncEngine.runOnce(manual: true)).called(1);
      verifyNever(() => syncStatusNotifier.checkForStuckSyncAndNotify());
    });

    test('manual sync reports failure through the health callback', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true))
          .thenThrow(StateError('cloud unavailable'));

      Object? reportedError;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        onSyncFailure: (error, _) => reportedError = error,
      );

      await expectLater(triggers.syncNow(), throwsA(isA<StateError>()));
      expect(reportedError, isA<StateError>());
    });

    test('restore reconciliation runs before readiness is required', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});
      final pulls = <int>[];
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => false,
        pullFromServer: () async => pulls.add(1),
        connectivity: connectivity,
      );

      await triggers.reconcileAfterRestore();

      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
      expect(pulls, [1]);
    });

    test('restore reconciliation propagates reconciliation failure', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenThrow(StateError('reconciliation failed'));
      final pulls = <int>[];
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        pullFromServer: () async => pulls.add(1),
        connectivity: connectivity,
      );

      await expectLater(
        triggers.reconcileAfterRestore(),
        throwsA(isA<StateError>()),
      );
      expect(pulls, isEmpty);
      verifyNever(() => syncStatusNotifier.checkForStuckSyncAndNotify());
    });

    test('restore reconciliation refuses to advertise success offline', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );

      await expectLater(triggers.reconcileAfterRestore(), throwsA(isA<StateError>()));
      verifyNever(() => syncEngine.runOnce(manual: any(named: 'manual')));
    });

    test('serializes a trigger already started by enabling sync during restore', () async {
      SharedPreferences.setMockInitialValues({});
      final config = await SyncConfig.load();
      final runStarted = Completer<void>();
      final releaseRun = Completer<void>();
      var runCount = 0;
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      when(() => syncEngine.runOnce(manual: any(named: 'manual'))).thenAnswer((_) async {
        runCount++;
        if (!runStarted.isCompleted) runStarted.complete();
        await releaseRun.future;
      });

      final pulls = <int>[];
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        pullFromServer: () async => pulls.add(1),
        connectivity: connectivity,
      );

      await triggers.start();
      unawaited(config.setEnabled(true));
      await runStarted.future;

      final restoreRun = triggers.reconcileAfterRestore();
      await Future<void>.delayed(Duration.zero);
      expect(runCount, 1);
      expect(pulls, isEmpty);

      releaseRun.complete();
      await restoreRun;

      expect(runCount, 1);
      expect(pulls, [1]);
      verify(() => syncEngine.runOnce(manual: false)).called(1);
      triggers.dispose();
    });

    test('restore reconciliation runs after a trigger blocked in readiness', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => const Stream.empty());
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});

      final readinessStarted = Completer<void>();
      final releaseReadiness = Completer<void>();
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => false,
        onNotReady: () async {
          if (!readinessStarted.isCompleted) readinessStarted.complete();
          await releaseReadiness.future;
        },
        connectivity: connectivity,
      );

      unawaited(triggers.start());
      await readinessStarted.future;

      final restore = triggers.reconcileAfterRestore();
      await Future<void>.delayed(Duration.zero);
      verifyNever(() => syncEngine.runOnce(manual: false));

      releaseReadiness.complete();
      await restore;

      verify(() => syncEngine.runOnce(manual: false)).called(1);
      triggers.dispose();
    });

    test('concurrent restore reconciliations await the same in-flight run', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      final runStarted = Completer<void>();
      final releaseRun = Completer<void>();
      when(() => syncEngine.runOnce(manual: any(named: 'manual'))).thenAnswer((_) async {
        if (!runStarted.isCompleted) runStarted.complete();
        await releaseRun.future;
      });

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        connectivity: connectivity,
      );

      final first = triggers.reconcileAfterRestore();
      await runStarted.future;
      final second = triggers.reconcileAfterRestore();

      releaseRun.complete();
      await Future.wait([first, second]);

      verify(() => syncEngine.runOnce(manual: false)).called(1);
      verify(() => syncStatusNotifier.checkForStuckSyncAndNotify()).called(1);
      triggers.dispose();
    });

    test('reports failed post-recovery delta pull', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      when(() => syncEngine.runOnce(manual: true)).thenAnswer((_) async {});

      var pullCalls = 0;
      Object? recoveryFailure;
      final triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => true,
        pullFromServer: () async {
          pullCalls++;
          if (pullCalls == 1) {
            throw const BusinessRuleFailure(
              'stale cursor',
              code: 'SYNC_CURSOR_TOO_OLD',
            );
          }
          throw StateError('delta pull failed');
        },
        onCursorTooOldRecovery: () async {},
        onRecoveryFailed: (error) async {
          recoveryFailure = error;
        },
      );

      await expectLater(triggers.syncNow(), throwsA(isA<StateError>()));

      expect(pullCalls, 2);
      expect(recoveryFailure, isA<StateError>());
      triggers.dispose();
    });

    test('retries readiness after startup initialization fails', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      final connectivityChanges = StreamController<List<ConnectivityResult>>();
      when(() => connectivity.onConnectivityChanged)
          .thenAnswer((_) => connectivityChanges.stream);
      when(() => connectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => syncEngine.runOnce(manual: any(named: 'manual')))
          .thenAnswer((_) async {});

      var initializationCalls = 0;
      var ready = false;
      final readinessCompleted = Completer<void>();
      late final SyncTriggers triggers;
      triggers = SyncTriggers(
        syncEngine: syncEngine,
        syncConfig: config,
        syncStatusNotifier: syncStatusNotifier,
        isReady: () async => ready,
        onNotReady: () async {
          initializationCalls++;
          if (initializationCalls == 1) {
            throw StateError('startup initialization failed');
          }
          await triggers.reconcileForReadiness();
          ready = true;
          if (!readinessCompleted.isCompleted) {
            readinessCompleted.complete();
          }
        },
        connectivity: connectivity,
      );

      await expectLater(triggers.start(), throwsA(isA<StateError>()));
      expect(initializationCalls, 1);
      verifyNever(() => syncEngine.runOnce(manual: any(named: 'manual')));

      connectivityChanges.add([ConnectivityResult.wifi]);
      await untilCalled(() => syncEngine.runOnce(manual: any(named: 'manual')));
      await readinessCompleted.future;

      expect(initializationCalls, 2);
      expect(ready, isTrue);
      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce(manual: false)).called(1);

      triggers.dispose();
      await connectivityChanges.close();
    });
  });
}