import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single persisted answer to "is Fulus Cloud sync enabled on this
/// installation?". The value is intentionally local and non-sensitive.
///
/// SyncService owns the lifecycle reaction to this setting. SyncConfig only
/// persists the switch and notifies its owner when that switch changes.
class SyncConfig extends ChangeNotifier {
  SyncConfig({required SharedPreferences preferences}) : _preferences = preferences;

  static Future<SyncConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SyncConfig(preferences: preferences);
  }

  final SharedPreferences _preferences;
  static const _isEnabledKey = 'fulus_sync_enabled';

  bool get isEnabled => _preferences.getBool(_isEnabledKey) ?? false;

  /// Changes the persisted switch and notifies SyncService so the running
  /// synchronization lifecycle can react. The setting itself performs no
  /// network I/O.
  Future<void> setEnabled(bool value) async {
    if (isEnabled == value) return;
    await _preferences.setBool(_isEnabledKey, value);
    notifyListeners();
  }
}
