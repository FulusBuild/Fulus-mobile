import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pin_hasher.dart';

/// Gap fix — Volume 11 names "App Lock" and Batch 6 of the visual bible
/// has an "App Lock Unlock" screen; neither existed. This is local-only
/// and deliberately separate from ApprovalPinRepository/SecureStorage's
/// approval-PIN verifiers: those are business-level reference data
/// ("which owners exist, synced from the backend, checked when ANY
/// device needs an in-person approval"), not this device's own
/// screen-lock. App Lock never leaves this device, never syncs, and one
/// employee's app-lock PIN has nothing to do with another's — so it
/// gets its own small `FlutterSecureStorage` instance rather than
/// extending SecureStorage's, respecting that class's own header
/// comment about staying narrowly scoped to what it currently holds.
///
/// Uses [Argon2PinHasher] — the same pure-Dart, no-native-library
/// implementation ApprovalPinRepository uses, for the same reason (see
/// that class's own doc comment: dargon2_flutter is confirmed broken on
/// Android). The PIN itself is never stored, only its hash and salt.
class AppLockConfig {
  AppLockConfig({
    required SharedPreferences preferences,
    PinHasher? pinHasher,
    FlutterSecureStorage? secureStorage,
  })  : _preferences = preferences,
        _pinHasher = pinHasher ?? const Argon2PinHasher(),
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  final SharedPreferences _preferences;
  final PinHasher _pinHasher;
  final FlutterSecureStorage _secureStorage;

  static const _enabledKey = 'fulus_app_lock_enabled';
  static const _hashKey = 'fulus_app_lock_pin_hash';
  static const _saltKey = 'fulus_app_lock_pin_salt';

  static Future<AppLockConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppLockConfig(preferences: prefs);
  }

  /// Whether the lock should actually engage — both a PIN being set AND
  /// the flag being on, so a half-finished "set PIN, then killed the
  /// app before finishing" never locks someone out with no PIN to enter.
  Future<bool> isActive() async {
    if (!(_preferences.getBool(_enabledKey) ?? false)) return false;
    return (await _secureStorage.read(key: _hashKey)) != null;
  }

  Future<bool> hasPinSet() async => (await _secureStorage.read(key: _hashKey)) != null;

  Future<void> setPin(String pin) async {
    final hashed = await _pinHasher.hash(pin);
    await _secureStorage.write(key: _hashKey, value: hashed.hash);
    await _secureStorage.write(key: _saltKey, value: hashed.salt);
    await _preferences.setBool(_enabledKey, true);
  }

  Future<bool> verifyPin(String pin) async {
    final hash = await _secureStorage.read(key: _hashKey);
    final salt = await _secureStorage.read(key: _saltKey);
    if (hash == null || salt == null) return false;
    return _pinHasher.verify(pin, expectedHash: hash, salt: salt);
  }

  /// Turns the lock off without discarding the PIN, so re-enabling
  /// later doesn't require setting a new one — mirrors how disabling
  /// Sync (SyncConfig.setEnabled(false)) leaves queued data intact
  /// rather than deleting it.
  Future<void> setEnabled(bool value) => _preferences.setBool(_enabledKey, value);

  Future<void> removePin() async {
    await _preferences.setBool(_enabledKey, false);
    await _secureStorage.delete(key: _hashKey);
    await _secureStorage.delete(key: _saltKey);
  }
}
