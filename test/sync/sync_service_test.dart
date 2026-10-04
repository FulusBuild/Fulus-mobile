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

  test('restore enable arms the restore gate before enabling sync', () async {
    final config = await SyncConfig.load();
    final events = <String>[];
    when(() => runtime.beginRestoreReconciliation()).thenAnswer((_) {
      events.add('begin');
    });
    when(() => runtime.start()).thenAnswer((_) async {
      events.add('start');
    });
    when(() => runtime.cancelRestoreReconciliation()).thenAnswer((_) {
      events.add('cancel');
    });

    final service = SyncService(runtime, config);
    await service.bootstrap();
    await service.enableForRestore();

    expect(events, ['begin', 'start']);
    expect(service.isEnabled, isTrue);

    service.cancelRestore();
    expect(events, ['begin', 'start', 'cancel']);
    service.dispose();
  });
}
