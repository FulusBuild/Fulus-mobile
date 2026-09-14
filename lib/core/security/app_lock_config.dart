import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pin_hasher.dart';

/// Local-only configuration for Fulus App Lock.
///
/// The PIN is hashed and salted; biometric data is never stored by Fulus.
/// Android/iOS own biometric enrollment and verification.
class AppLockConfig {
  AppLockConfig({
    required SharedPreferences preferences,
    PinHasher? pinHasher,
    FlutterSecureStorage? secureStorage,
  })  : _preferences = preferences,
        _pinHasher = pinHasher ?? const Argon2PinHasher(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  final SharedPreferences _preferences;
  final PinHasher _pinHasher;
  final FlutterSecureStorage _secureStorage;

  static const _enabledKey = 'fulus_app_lock_enabled';
  static const _biometricEnabledKey = 'fulus_app_lock_biometric_enabled';
  static const _hashKey = 'fulus_app_lock_pin_hash';
  static const _saltKey = 'fulus_app_lock_pin_salt';

  static Future<AppLockConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppLockConfig(preferences: prefs);
  }

  Future<bool> isActive() async {
    if (!(_preferences.getBool(_enabledKey) ?? false)) return false;
    return (await _secureStorage.read(key: _hashKey)) != null;
  }

  Future<bool> hasPinSet() async => (await _secureStorage.read(key: _hashKey)) != null;

  Future<bool> isBiometricEnabled() async =>
      (await isActive()) && (_preferences.getBool(_biometricEnabledKey) ?? false);

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

  Future<void> setBiometricEnabled(bool value) async {
    await _preferences.setBool(_biometricEnabledKey, value);
  }

  Future<void> setEnabled(bool value) => _preferences.setBool(_enabledKey, value);

  Future<void> removePin() async {
    await _preferences.setBool(_enabledKey, false);
    await _preferences.setBool(_biometricEnabledKey, false);
    await _secureStorage.delete(key: _hashKey);
    await _secureStorage.delete(key: _saltKey);
  }
}
