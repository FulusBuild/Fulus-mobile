import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_service.dart';
import 'package:fulus_mobile/sync/sync_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSyncRuntime extends Mock implements SyncRuntime {}

void main() {
  late MockSyncRuntime runtime;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    runtime = MockSyncRuntime();
  });

  test('bootstrap is idempotent and starts enabled synchronization once', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
    final config = await SyncConfig.load();
    when(() => runtime.start()).thenAnswer((_) async {});

    final service = SyncService(runtime, config);

    await service.bootstrap();
    await service.bootstrap();

    verify(() => runtime.start()).called(1);
    verifyNever(() => runtime.stop());
    service.dispose();
  });

  test('cloud bootstrap delegates through service', () async {\n    final config = await SyncConfig.load();\n    var calls = 0;\n    final service = SyncService(runtime, config, bootstrapCloud: () async { calls++; return true; });\n    await service.bootstrapCloud();\n    expect(calls, 1);\n    service.dispose();\n  });\n\n  test('disposed service cannot be bootstrapped or requested again', () async {
    final config = await SyncConfig.load();
    when(() => runtime.start()).thenAnswer((_) async {});
    when(() => runtime.request()).thenAnswer((_) async {});
    when(() => runtime.dispose()).thenReturn(null);

    final service = SyncService(runtime, config);
    await service.bootstrap();
    service.dispose();
    service.dispose();

    expect(
      () => service.bootstrap(),
      throwsA(isA<StateError>()),
    );
    expect(
      () => service.request(),
      throwsA(isA<StateError>()),
    );
    await service.waitForIdle();
    verify(() => runtime.dispose()).called(1);
    verifyNever(() => runtime.request());
  });

  test('runtime enable and disable are owned by SyncService', () async {
    final config = await SyncConfig.load();
    when(() => runtime.start()).thenAnswer((_) async {});
    when(() => runtime.stop()).thenReturn(null);

    final service = SyncService(runtime, config);
    await service.bootstrap();

    await service.enable();
    await Future<void>.delayed(Duration.zero);
    verify(() => runtime.start()).called(1);

    await service.disable();
    verify(() => runtime.stop()).called(1);

    service.dispose();
  });

  test('enable propagates runtime startup failure', () async {\n    final config = await SyncConfig.load();\n    when(() => runtime.start()).thenAnswer((_) async {\n      throw StateError('startup failed');\n    });\n\n    final service = SyncService(runtime, config);\n    await service.bootstrap();\n\n    await expectLater(\n      service.enable(),\n      throwsA(isA<StateError>()),\n    );\n    service.dispose();\n  });\n\n  test('restore enable arms the restore gate before enabling sync', () async {
    final config = await SyncConfig.load();
    final events = <String>[];
    when(() => runtime.beginRestoreReconciliation()).thenAnswer((_) {
      events.add('begin');
    });
    when(() => runtime.start()).thenAnswer((_) async {
      events.add('start');
    });
    when(() => runtime.reconcileAfterRestore()).thenAnswer((_) async {
      events.add('reconcile');
    });
    when(() => runtime.cancelRestoreReconciliation()).thenAnswer((_) {
      events.add('cancel');
    });

    final service = SyncService(runtime, config);
    await service.bootstrap();
    await service.enableForRestore();

    expect(events, ['begin']);
    expect(service.isEnabled, isTrue);

    await service.reconcileAfterRestore();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['begin', 'reconcile', 'start']);

    // A completed restore consumes the reservation; a later cancellation is
    // intentionally a no-op.
    service.cancelRestore();
    expect(events, ['begin', 'reconcile', 'start']);
    service.dispose();
  });

  test('cloud bootstrap owns readiness transitions', () async {
    final config = await SyncConfig.load();
    final states = <SyncReadinessState>[];
    final service = SyncService(
      runtime,
      config,
      bootstrapCloud: () async => true,
      onReadinessChanged: (state, _) => states.add(state),
    );

    await service.bootstrapCloud();

    expect(service.isReady, isTrue);
    expect(service.readinessState, SyncReadinessState.ready);
    expect(states, [
      SyncReadinessState.bootstrapping,
      SyncReadinessState.ready,
    ]);
    service.dispose();
  });

  test('cloud bootstrap leaves service not ready when prerequisites are unavailable', () async {
    final config = await SyncConfig.load();
    final states = <SyncReadinessState>[];
    final service = SyncService(
      runtime,
      config,
      bootstrapCloud: () async => false,
      onReadinessChanged: (state, _) => states.add(state),
    );

    await service.bootstrapCloud();

    expect(service.isReady, isFalse);
    expect(service.readinessState, SyncReadinessState.notReady);
    expect(states, [
      SyncReadinessState.bootstrapping,
      SyncReadinessState.notReady,
    ]);
    service.dispose();
  });

  test('cloud bootstrap records readiness errors centrally', () async {
    final config = await SyncConfig.load();
    final states = <SyncReadinessState>[];
    final error = StateError('cloud bootstrap failed');
    final service = SyncService(
      runtime,
      config,
      bootstrapCloud: () async => throw error,
      onReadinessChanged: (state, reported) {
        states.add(state);
        if (state == SyncReadinessState.error) {
          expect(identical(reported, error), isTrue);
        }
      },
    );

    await expectLater(service.bootstrapCloud(), throwsA(same(error)));

    expect(service.isReady, isFalse);
    expect(service.readinessState, SyncReadinessState.error);
    expect(states, [
      SyncReadinessState.bootstrapping,
      SyncReadinessState.error,
    ]);
    service.dispose();
  });

}
