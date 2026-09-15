import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single persisted answer to "is Fulus Cloud sync enabled on this
/// installation?". The value is intentionally local and non-sensitive.
///
/// SyncConfig is reactive: SyncTriggers listens to this object, so enabling
/// sync does not require an application restart. This is important for cloud
/// restore, which enables sync only after the restored database and device
/// registration are known to be valid.
class SyncConfig extends ChangeNotifier {
  SyncConfig({required SharedPreferences preferences}) : _preferences = preferences;

  static Future<SyncConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SyncConfig(preferences: preferences);
  }

  final SharedPreferences _preferences;
  static const _isEnabledKey = 'fulus_sync_enabled';

  bool get isEnabled => _preferences.getBool(_isEnabledKey) ?? false;

  /// Changes the persisted switch and immediately notifies the running sync
  /// trigger service. The setting itself does not perform network I/O.
  Future<void> setEnabled(bool value) async {
    if (isEnabled == value) return;
    await _preferences.setBool(_isEnabledKey, value);
    notifyListeners();
  }
}
