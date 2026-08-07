import 'package:dio/dio.dart';

import '../../../domain/entities/approval_hash.dart';
import '../api_client.dart';

/// Was: POST /api/auth/login, /refresh, /logout too — verified directly
/// against backend/app/routers/auth.py. Architecture Redesign: login is
/// now checked entirely locally (AuthRepositoryImpl, against the Users
/// table, no server involved at all), so those three methods and the
/// LoginRequestDto/RefreshRequestDto/TokenResponseDto shapes they used
/// are gone, not just unused — they were JWT-shaped specifically, and
/// this app no longer has a JWT to issue, refresh, or invalidate
/// anywhere in it. A future networked "join an existing business over
/// LAN/cloud" flow (Sync layer, deferred) will need its OWN
/// authentication design for that specific hop — reviving these three
/// methods as-is would mean reviving the JWT model the redesign
/// specifically dropped, not reusing something still correct.
///
/// setApprovalPin/getApprovalHashes below are unaffected by any of this:
/// they were never part of the login/session mechanism — they're the
/// separate (and still genuinely networked, still genuinely Sync-layer)
/// mechanism for one device to learn which OTHER devices' owners can
/// approve a PIN check offline (Architecture Section 6). That's an
/// inherently multi-device concern no local-only redesign can eliminate
/// — see this project's notes on which concepts are structurally
/// multi-device versus which merely used to require a server by
/// implementation accident.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// POST /api/auth/approval-pin — the owner's own device pushes its
  /// locally-computed Argon2id hash+salt up, never the raw PIN. Needs
  /// the caller's own current session attached; exactly how that's
  /// authenticated for this one, still-networked hop is a Sync-layer
  /// design question of its own (no JWT left to attach here either),
  /// tracked separately rather than answered by this stage.
  Future<void> setApprovalPin({
    required String pinHash,
    required String pinSalt,
  }) async {
    try {
      await _client.dio.post(
        '/api/auth/approval-pin',
        data: SetApprovalPinRequestDto(pinHash: pinHash, pinSalt: pinSalt).toJson(),
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// GET /api/auth/approval-hashes — the "which owners exist and can
  /// approve" dataset every employee device syncs down (Architecture
  /// Section 6).
  Future<List<ApprovalHashEntryDto>> getApprovalHashes() async {
    try {
      final response = await _client.dio.get('/api/auth/approval-hashes');
      return ApprovalHashesResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      ).hashes;
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
