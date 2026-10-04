import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_service.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSyncTriggers extends Mock implements SyncTriggers {}

void main() {
  late MockSyncTriggers triggers;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    triggers = MockSyncTriggers();
  });

  test('bootstrap is idempotent and starts enabled synchronization once', () async {
    SharedPreferences.setMockInitialValues({'fulus_sync_enabled': true});
    final config = await SyncConfig.load();
    when(() => triggers.start()).thenAnswer((_) async {});

    final service = SyncService(triggers, config);

    await service.bootstrap();
    await service.bootstrap();

    verify(() => triggers.start()).called(1);
    verifyNever(() => triggers.stop());
    service.dispose();
  });

  test('runtime enable and disable are owned by SyncService', () async {
    final config = await SyncConfig.load();
    when(() => triggers.start()).thenAnswer((_) async {});
    when(() => triggers.stop()).thenReturn(null);

    final service = SyncService(triggers, config);
    await service.bootstrap();

    await service.enable();
    await Future<void>.delayed(Duration.zero);
    verify(() => triggers.start()).called(1);

    await service.disable();
    verify(() => triggers.stop()).called(1);

    service.dispose();
  });

  test('restore enable arms the restore gate before enabling sync', () async {
    final config = await SyncConfig.load();
    final events = <String>[];
    when(() => triggers.beginRestoreReconciliation()).thenAnswer((_) {
      events.add('begin');
    });
    when(() => triggers.start()).thenAnswer((_) async {
      events.add('start');
    });
    when(() => triggers.cancelRestoreReconciliation()).thenAnswer((_) {
      events.add('cancel');
    });

    final service = SyncService(triggers, config);
    await service.bootstrap();
    await service.enableForRestore();

    expect(events, ['begin', 'start']);
    expect(service.isEnabled, isTrue);

    service.cancelRestore();
    expect(events, ['begin', 'start', 'cancel']);
    service.dispose();
  });
}
