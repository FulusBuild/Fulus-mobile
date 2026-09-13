import 'package:local_auth/local_auth.dart';

/// Device-level biometric authentication for quick, private access to Fulus.
///
/// This never stores a fingerprint or any biometric data. Android/iOS own
/// the biometric enrollment and return only whether the device owner passed
/// the system authentication prompt.
class BiometricAuth {
  BiometricAuth({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  Future<bool> isAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      return (await _localAuth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Use your fingerprint to unlock Fulus',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
