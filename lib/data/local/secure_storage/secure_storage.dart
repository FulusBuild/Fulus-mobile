import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/entities/approval_hash.dart';

/// Wraps flutter_secure_storage (Android Keystore-backed) for two
/// categories of data: the refresh token (Architecture Section 6) and
/// the offline approval-PIN verifiers (Architecture Section 11). This
/// mirrors the exact same scoping discipline verified directly in the
/// desktop app's own secrets.rs during the prior audit: that file
/// exposes secure_token_set/get/delete for precisely the JWT refresh
/// token, not a general-purpose key-value store other parts of the app
/// reach for by default. The general Drift database (Architecture
/// Section 3) is the default for everything else, deliberately, per
/// Section 11's own stated reasoning — Android's app-sandboxing is the
/// primary protection for most local data, and reaching for
/// Keystore-backed storage everywhere would both be unnecessary
/// overhead and obscure which things in this app genuinely need the
/// stronger guarantee.
///
/// IMPORTANT — found during a self-audit pass, after Stage 4: the
/// refresh-token methods below are no longer called by
/// AuthRepositoryImpl at all (Stage 2 moved login entirely local — see
/// that class's own doc comment). They're still called, though, by
/// ApiClient's own auth interceptor, which independently reads/writes/
/// deletes a refresh token for its (currently dormant) 401-refresh
/// flow — see api_client.dart's class doc comment for the full picture.
/// In practice, getRefreshToken() will always return null now, since
/// nothing in the app writes one anymore. Not removed here: doing so
/// would break ApiClient's compilation, since it still calls all three.
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
  // Currently only ever read/written by ApiClient's own dormant auth
  // interceptor (see this class's own doc comment) — AuthRepositoryImpl
  // doesn't reference SecureStorage at all since Stage 2's redesign.

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

  /// STALE COMMENT CORRECTED (self-audit pass, after Stage 4): this used
  /// to say "called on logout" — confirmed by grepping the whole repo,
  /// nothing calls this at all right now, on logout or otherwise. It
  /// also shouldn't be wired to a normal per-user logout under the local
  /// multi-account model Stage 2 introduced: these verifiers are
  /// business-level reference data ("which owners exist on this
  /// device"), not per-session credentials — one employee logging out
  /// on a shared till (Volume 9) must not wipe the data the NEXT
  /// signed-in user on the same device still needs for offline approval
  /// checks. Kept as an available method for a real future use (e.g. an
  /// owner forcing a fresh re-sync, or an eventual "reset this device"
  /// flow), just not currently called from anywhere.
  Future<void> deleteApprovalPinVerifiers() async {
    await _storage.delete(key: _approvalPinVerifiersKey);
  }

  /// STALE COMMENT CORRECTED (self-audit pass, after Stage 4): this used
  /// to say "used on logout" — confirmed by grepping the whole repo,
  /// nothing calls this at all. It also shouldn't be wired to
  /// AuthRepositoryImpl.logout() the way it might sound like it should:
  /// wiping approvalPinVerifiers on every logout would incorrectly erase
  /// business-level data the NEXT signed-in user on the same shared till
  /// still needs (see deleteApprovalPinVerifiers' own doc comment right
  /// above). Kept available for a genuinely different, more drastic
  /// operation than a normal logout — e.g. a future "remove this
  /// business from this device entirely" flow — which doesn't exist as
  /// a feature yet either.
  Future<void> clearAll() => _storage.deleteAll();
}
