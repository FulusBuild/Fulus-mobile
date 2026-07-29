import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/entities/approval_hash.dart';

/// Wraps flutter_secure_storage (Android Keystore-backed) for the two
/// categories of data Architecture Sections 6 and 11 specifically require
/// this treatment for — the refresh token and the offline approval-PIN
/// verifiers — and nothing else. This mirrors the exact same scoping
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

  static const _refreshTokenKey = 'fulus_refresh_token';
  static const _approvalPinVerifiersKey = 'fulus_approval_pin_verifiers';

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

  // --- Approval PIN verifiers (Architecture Section 6) ---
  //
  // The owners' PINs themselves are NEVER stored anywhere, on this
  // device or any other, matching the architecture document's explicit
  // statement: "The backend never stores or transmits the raw PIN."
  // What's stored here is each admin's Argon2id hash and its salt,
  // synced down from the backend's GET /api/auth/approval-hashes (now
  // built — see auth_api.dart) as "which owners exist and can approve."
  //
  // A LIST, not a single hash/salt pair — this replaces an earlier
  // version of this file that stored exactly one verifier, under the
  // (incorrect) assumption of a single owner. A business can genuinely
  // have more than one admin, each with their own PIN, and the sync-down
  // dataset is a list for exactly that reason. Stored as one JSON-
  // encoded blob under a single key rather than one secure-storage key
  // per user: the realistic count of owners for a small business is a
  // handful at most, so a single small JSON blob is a better fit than
  // managing a dynamically-growing set of individually-keyed entries —
  // and it's still Keystore-backed as a whole, which is what actually
  // matters here (see Argon2PinHasher's own doc comment on why a 4-digit
  // PIN's hash is more sensitive than it first looks, and worth this
  // treatment despite being a list rather than one scalar secret).
  //
  // This is genuinely different data from the refresh token above —
  // it's not this device's own credential, it's every synced owner's
  // verifier, needed so an in-person PIN entry on an EMPLOYEE's device
  // can be checked with zero network round-trip. Kept in the same
  // Keystore-backed store as the refresh token because both are
  // authentication material where a plain-SQLite-row compromise would
  // be a real escalation, not because they're conceptually the same
  // kind of secret.

  Future<void> setApprovalPinVerifiers(List<ApprovalPinVerifier> verifiers) async {
    final json = jsonEncode(verifiers.map((v) => v.toJson()).toList());
    await _storage.write(key: _approvalPinVerifiersKey, value: json);
  }

  Future<List<ApprovalPinVerifier>> getApprovalPinVerifiers() async {
    final json = await _storage.read(key: _approvalPinVerifiersKey);
    if (json == null) return const [];
    final decoded = jsonDecode(json) as List<dynamic>;
    return decoded
        .map((e) => ApprovalPinVerifier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Called on logout and before writing a freshly-synced set — always
  /// the full list is replaced via setApprovalPinVerifiers, never
  /// merged, so a synced-down entry that no longer exists server-side
  /// (an admin's PIN was reset, say) can't linger indefinitely as a
  /// stale, still-matchable verifier.
  Future<void> deleteApprovalPinVerifiers() async {
    await _storage.delete(key: _approvalPinVerifiersKey);
  }

  /// Full wipe — used on logout. Deliberately does not selectively clear
  /// only some keys, since a partially-cleared secure store after logout
  /// (e.g. a stale refresh token surviving) would be a real security
  /// regression, not just an inconsistency.
  Future<void> clearAll() => _storage.deleteAll();
}
