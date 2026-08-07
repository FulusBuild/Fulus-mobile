import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences.setMockInitialValues is the package's own
/// long-standing testing utility (no platform channel needed once set)
/// — the standard way to test a shared_preferences-backed class without
/// a real device.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isEnabled defaults to false on a fresh install — Stage 16\'s core claim', () async {
    final config = await SyncConfig.load();
    expect(config.isEnabled, isFalse);
  });

  test('setEnabled(true) then isEnabled reflects it immediately', () async {
    final config = await SyncConfig.load();
    await config.setEnabled(true);
    expect(config.isEnabled, isTrue);
  });

  test('the toggle persists across a fresh SyncConfig.load()', () async {
    final first = await SyncConfig.load();
    await first.setEnabled(true);

    final second = await SyncConfig.load();
    expect(second.isEnabled, isTrue);
  });

  test('setEnabled(false) can turn it back off', () async {
    final config = await SyncConfig.load();
    await config.setEnabled(true);
    await config.setEnabled(false);
    expect(config.isEnabled, isFalse);
  });
}
