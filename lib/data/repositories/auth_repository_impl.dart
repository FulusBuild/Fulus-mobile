import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/secure_storage/secure_storage.dart';
import '../remote/api_client.dart';
import '../remote/endpoints/auth_api.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthApi authApi,
    required ApiClient apiClient,
    required SecureStorage secureStorage,
  })  : _authApi = authApi,
        _apiClient = apiClient,
        _secureStorage = secureStorage;

  final AuthApi _authApi;
  final ApiClient _apiClient;
  final SecureStorage _secureStorage;

  AuthUser? _currentUser;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthUser?> restoreSession() async {
    final refreshToken = await _secureStorage.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await _authApi.refresh(refreshToken: refreshToken);
      await _applySuccessfulAuth(response);
      return _currentUser;
    } on AuthFailure {
      // The stored refresh token is genuinely no longer valid (expired,
      // or the user was deactivated server-side per
      // auth_service.refresh_access_token) — cleared so a later launch
      // doesn't keep retrying a token that will never work.
      await _secureStorage.deleteRefreshToken();
      return null;
    } on Failure {
      // Anything else (NetworkFailure: no connectivity, or the server
      // genuinely unreachable right now) says nothing about whether the
      // refresh token itself is valid — deliberately NOT deleted. No
      // session is established for THIS launch (no access token exists
      // to attach to a request right now), but the stored refresh token
      // survives so ApiClient's own reactive 401-refresh (already built
      // into the auth interceptor) can succeed with it later, the
      // moment connectivity actually returns and the sync engine's own
      // triggers attempt a real request — exactly Phase 0's own exit
      // criterion (offline create -> restart -> reconnect).
      return null;
    }
  }

  @override
  Future<AuthUser> login({
    required String username,
    required String password,
  }) async {
    final response = await _authApi.login(username: username, password: password);
    await _applySuccessfulAuth(response);
    return _currentUser!;
  }

  @override
  Future<void> logout() async {
    try {
      await _authApi.logout();
    } catch (_) {
      // Best-effort only — see AuthRepository.logout's own doc comment
      // on why a failed audit-log call must never block the local
      // logout from completing.
    }
    _apiClient.setAccessToken(null);
    await _secureStorage.deleteRefreshToken();
    _currentUser = null;
  }

  Future<void> _applySuccessfulAuth(TokenResponseDto response) async {
    _apiClient.setAccessToken(response.accessToken);
    // Refresh token ROTATION (verified directly: auth_service.py's
    // refresh_access_token issues a brand-new one on every call, not a
    // reused one) — always re-stored here, on both login and refresh,
    // never assumed unchanged.
    await _secureStorage.setRefreshToken(response.refreshToken);
    _currentUser = response.user.toDomain();
  }
}
