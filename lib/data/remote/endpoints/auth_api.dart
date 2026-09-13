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

  /// Optional cloud connection. Local PIN authentication is never involved;
  /// the caller supplies a portable credential only for this connection hop.
  /// The password is sent directly to Supabase Auth over TLS and is never
  /// persisted by Fulus. Only the refresh token is retained in secure storage.
  Future<ServerAuthSessionDto> connectServer({
    required String email,
    required String password,
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      final response = await authClient.post(
        '/auth/v1/token?grant_type=password',
        data: {'email': email, 'password': password},
        options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}),
      );
      final data = response.data as Map<String, dynamic>;
      final session = ServerAuthSessionDto.fromJson(data);
      await _client.setServerAccessToken(session.accessToken);
      await _client.persistServerRefreshToken(session.refreshToken);
      return session;
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// Creates a Fulus Cloud account using Supabase Auth.
  /// Returns a session when email confirmation is disabled; otherwise the
  /// returned user is unconfirmed and the UI can ask the user to verify.
  Future<ServerSignUpResult> signUpServer({
    required String email,
    required String password,
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      final response = await authClient.post(
        '/auth/v1/signup',
        data: {'email': email, 'password': password},
        options: Options(headers: {
          'apikey': publishableKey,
          'content-type': 'application/json',
        }),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final user = data['user'] as Map<String, dynamic>?;
      if (accessToken != null && refreshToken != null && user != null) {
        final session = ServerAuthSessionDto(
          accessToken: accessToken,
          refreshToken: refreshToken,
          userId: user['id'] as String,
        );
        await _client.setServerAccessToken(session.accessToken);
        await _client.persistServerRefreshToken(session.refreshToken);
        return ServerSignUpResult(session: session, emailConfirmed: user['email_confirmed_at'] != null);
      }
      return ServerSignUpResult(
        session: null,
        emailConfirmed: user?['email_confirmed_at'] != null,
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// Restores an optional server session using only the secure refresh token.
  /// If none exists, the app remains fully local and this returns null.
  Future<ServerAuthSessionDto?> restoreServerSession({
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final refreshToken = await _client.secureRefreshToken();
    if (refreshToken == null) return null;
    final authClient = Dio(BaseOptions(baseUrl: supabaseUrl));
    try {
      final response = await authClient.post(
        '/auth/v1/token?grant_type=refresh_token',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {'apikey': publishableKey, 'content-type': 'application/json'}),
      );
      final session = ServerAuthSessionDto.fromJson(response.data as Map<String, dynamic>);
      await _client.setServerAccessToken(session.accessToken);
      await _client.persistServerRefreshToken(session.refreshToken);
      return session;
    } on DioException {
      await _client.clearServerRefreshToken();
      _client.setAccessToken(null);
      return null;
    }
  }

  Future<Map<String, dynamic>> registerCloudDevice({
    required String businessId,
    required String deviceClientId,
    required String deviceName,
    required String platform,
    required String appVersion,
    required String functionBaseUrl,
    required String publishableKey,
  }) async {
    try {
      final response = await Dio(BaseOptions(baseUrl: functionBaseUrl)).post(
        '',
        data: {
          'action': 'register_device',
          'business_id': businessId,
          'device_client_id': deviceClientId,
          'device_name': deviceName,
          'platform': platform,
          'app_version': appVersion,
        },
        options: Options(headers: {
          'apikey': publishableKey,
          'Authorization': 'Bearer ${_client.serverAccessToken}',
          'content-type': 'application/json',
        }),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}

class ServerAuthSessionDto {
  const ServerAuthSessionDto({required this.accessToken, required this.refreshToken, required this.userId});
  final String accessToken;
  final String refreshToken;
  final String userId;

  factory ServerAuthSessionDto.fromJson(Map<String, dynamic> json) => ServerAuthSessionDto(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    userId: (json['user'] as Map<String, dynamic>)['id'] as String,
  );
}
\nclass ServerSignUpResult {
  const ServerSignUpResult({required this.session, required this.emailConfirmed});
  final ServerAuthSessionDto? session;
  final bool emailConfirmed;
}\n