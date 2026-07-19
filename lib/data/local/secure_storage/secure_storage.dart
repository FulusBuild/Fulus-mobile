import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage (Android Keystore-backed) for the two
/// categories of data Architecture Sections 6 and 11 specifically require
/// this treatment for — the refresh token and the offline approval-PIN
/// hash — and nothing else. This mirrors the exact same scoping
/// discipline I verified directly in the desktop app's own secrets.rs
/// during the prior audit: that file exposes secure_token_set/get/delete
/// for precisely the JWT refresh token, not a general-purpose key-value
/// store other parts of the app reach for by default. The general Drift
/// database (Architecture Section 3) is the default for everything else,
/// deliberately, per Section 11's own stated reasoning — Android's
/// app-sandboxing is the primary protection for most local data, and
/// reaching for Keystore-backed storage everywhere would both be
/// unnecessary overhead and obscure which two things in this app
/// genuinely need the stronger guarantee.
class SecureStorage {
  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _refreshTokenKey = 'bms_refresh_token';
  static const _approvalPinHashKey = 'bms_approval_pin_hash';
  static const _approvalPinSaltKey = 'bms_approval_pin_salt';

  // --- Refresh token (Architecture Section 6) ---
  //
  // The access token is deliberately NOT stored here or anywhere on
  // disk — Architecture Section 6 is explicit it's held in memory only
  // (a Riverpod provider), gone the moment the app process ends, and
  // reconstructed via a silent refresh on next launch. Only the
  // longer-lived refresh token needs to survive a process restart, and
  // only it gets Keystore-backed storage.

  Future<void> setRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> deleteRefreshToken() => _storage.delete(key: _refreshTokenKey);

  // --- Approval PIN hash (Architecture Section 6) ---
  //
  // The owner's PIN itself is NEVER stored anywhere, on this device or
  // any other, matching the architecture document's explicit statement:
  // "The backend never stores or transmits the raw PIN." What's stored
  // here is the Argon2id hash and its salt, synced down from the backend
  // as part of the approval-hashes dataset (Architecture Section 6's
  // named backend gap: GET /api/auth/business/{id}/approval-hashes,
  // which does not exist in the backend yet as of this phase).
  //
  // This is genuinely different data from the refresh token above —
  // it's not this device's own credential, it's every synced owner's
  // verifier, needed so an in-person PIN entry on an EMPLOYEE's device
  // can be checked with zero network round-trip. Kept in the same
  // Keystore-backed store as the refresh token because both are
  // authentication material where a plain-SQLite-row compromise would
  // be a real escalation, not because they're conceptually the same
  // kind of secret.

  Future<void> setApprovalPinVerifier({
    required String hash,
    required String salt,
  }) async {
    await _storage.write(key: _approvalPinHashKey, value: hash);
    await _storage.write(key: _approvalPinSaltKey, value: salt);
  }

  Future<({String hash, String salt})?> getApprovalPinVerifier() async {
    final hash = await _storage.read(key: _approvalPinHashKey);
    final salt = await _storage.read(key: _approvalPinSaltKey);
    if (hash == null || salt == null) return null;
    return (hash: hash, salt: salt);
  }

  /// Called on logout and on the owner-approval-hash resync path — never
  /// called partially (hash without salt or vice versa), since a
  /// mismatched pair would make every subsequent PIN check silently and
  /// permanently fail rather than cleanly report "no verifier available."
  Future<void> deleteApprovalPinVerifier() async {
    await _storage.delete(key: _approvalPinHashKey);
    await _storage.delete(key: _approvalPinSaltKey);
  }

  /// Full wipe — used on logout. Deliberately does not selectively clear
  /// only some keys, since a partially-cleared secure store after logout
  /// (e.g. a stale refresh token surviving) would be a real security
  /// regression, not just an inconsistency.
  Future<void> clearAll() => _storage.deleteAll();
}
