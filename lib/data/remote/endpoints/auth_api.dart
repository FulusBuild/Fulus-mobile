import 'package:dio/dio.dart';

import '../../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../api_client.dart';

/// POST /api/auth/login, POST /api/auth/refresh, POST /api/auth/logout —
/// verified directly against backend/app/routers/auth.py.
class AuthApi {
  AuthApi(this._client)
      : _bareDio = Dio(BaseOptions(baseUrl: _client.dio.options.baseUrl));

  final ApiClient _client;

  /// login() and refresh() deliberately do NOT use _client.dio — that
  /// instance has the auth interceptor attached, and the auth
  /// interceptor's own onError already reacts to any 401 by attempting
  /// its own refresh-and-retry. If THIS call (a login attempt, or a
  /// proactive refresh at app launch) itself 401'd through the shared
  /// client, the interceptor would kick in on top of it — confusing,
  /// unintended double-handling. This mirrors the exact reasoning
  /// already documented on the interceptor's own internal refresh call
  /// in api_client.dart: "a bare, uninterceptored Dio call for the
  /// refresh itself... to avoid a refresh call that itself 401s
  /// recursively triggering another refresh attempt."
  final Dio _bareDio;

  /// Distinguishes a login-specific 401 (wrong username/password —
  /// AuthFailure.invalidCredentials()) from ApiClient.mapError's own
  /// general 401 case (AuthFailure.sessionExpired(), meant for an
  /// ALREADY-authenticated request whose refresh also failed) — the
  /// same "the calling endpoint special-cases before falling back to
  /// the general mapper" pattern SalesApi.createSale already
  /// established for its own 409 case, applied here for the same
  /// underlying reason: a single status code means genuinely different
  /// things depending on which endpoint produced it.
  Future<TokenResponseDto> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _bareDio.post(
        '/api/auth/login',
        data: LoginRequestDto(username: username, password: password).toJson(),
      );
      return TokenResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthFailure.invalidCredentials();
      }
      throw _client.mapError(e);
    }
  }

  /// A 401 here means the stored refresh token itself is no longer
  /// valid (expired, or the user was deactivated server-side per
  /// auth_service.refresh_access_token) — genuinely session-expired,
  /// not an invalid-credentials case (no credentials are submitted to
  /// this endpoint at all) — so the general mapper's existing 401
  /// handling is exactly right here, deliberately NOT special-cased the
  /// way login() is above.
  Future<TokenResponseDto> refresh({required String refreshToken}) async {
    try {
      final response = await _bareDio.post(
        '/api/auth/refresh',
        data: RefreshRequestDto(refreshToken: refreshToken).toJson(),
      );
      return TokenResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// Unlike login/refresh, this genuinely should go through the shared,
  /// interceptor-attached client — it needs the current access token
  /// attached automatically (Authorization header), which only
  /// _client.dio's auth interceptor does. Per its own docstring in
  /// routers/auth.py, this call exists purely to record an audit-log
  /// entry — JWTs are stateless, so the backend has nothing to
  /// invalidate — which is why AuthRepositoryImpl treats this call as
  /// best-effort and clears the local session regardless of whether it
  /// succeeds.
  Future<void> logout() async {
    try {
      await _client.dio.post('/api/auth/logout');
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
