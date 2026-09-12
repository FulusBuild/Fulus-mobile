import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
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

void main() {
  late MockSyncEngine syncEngine;
  late MockConnectivity connectivity;
  late MockSyncStatusNotifier syncStatusNotifier;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    syncEngine = MockSyncEngine();
    connectivity = MockConnectivity();
    syncStatusNotifier = MockSyncStatusNotifier();
    when(() => syncStatusNotifier.checkForStuckSyncAndNotify())
        .thenAnswer((_) async {});
  });

  group('Stage 16 — sync disabled (the default)', () {
    test('start() never checks connectivity and never runs the engine', () async {
      final config = await SyncConfig.load();
      expect(config.isEnabled, isFalse); // the documented default

      final triggers = SyncTriggers(
        syncEngine: syncEngine,
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

      // syncNow() is `async`, so even though the throw happens before any
      // await, it never throws synchronously to this call site — Dart
      // wraps it into a failed Future instead. expectLater (not the bare
      // synchronous expect) is the pattern for asserting against that.
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

  group('Stage 16 — runtime toggle', () {
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

      await untilCalled(() => syncEngine.runOnce());
      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce()).called(1);
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

      // A second explicit trigger must be a no-op once disabled.
      await triggers.notifyEnqueued();
      verify(() => connectivity.checkConnectivity()).called(1);
    });
  });

  group('Stage 16 — sync enabled', () {
    test('start() checks connectivity and runs the engine when online', () async {
      SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
      final config = await SyncConfig.load();
      expect(config.isEnabled, isTrue);

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
      // start() -> _runIfOnline() fires the actual drain via
      // unawaited(_runAndCheckStuck()) (see sync_triggers.dart's own
      // comment on why: a slow/hanging drain must never block start()
      // itself from returning). That means `await triggers.start()`
      // completing does NOT guarantee runOnce() has been called yet —
      // asserting immediately after would be a race. untilCalled waits
      // specifically for that mock interaction instead of guessing at a
      // delay.
      await untilCalled(() => syncEngine.runOnce());

      verify(() => connectivity.checkConnectivity()).called(1);
      verify(() => syncEngine.runOnce()).called(1);
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
  });
}
