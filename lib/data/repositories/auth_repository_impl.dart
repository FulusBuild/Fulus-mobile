import 'package:drift/drift.dart';

import '../../core/errors/failure.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/database/database.dart';
import '../local/secure_storage/secure_storage.dart';
import '../remote/api_client.dart';
import '../remote/endpoints/auth_api.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthApi authApi,
    required ApiClient apiClient,
    required SecureStorage secureStorage,
    required AppDatabase db,
  })  : _authApi = authApi,
        _apiClient = apiClient,
        _secureStorage = secureStorage,
        _db = db;

  final AuthApi _authApi;
  final ApiClient _apiClient;
  final SecureStorage _secureStorage;
  final AppDatabase _db;

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
      // doesn't keep retrying a token that will never work. The cached
      // Sessions row is cleared for the same reason: presenting
      // "logged in as X" from local cache when the account is actually
      // deactivated/expired would be actively misleading, not just
      // stale.
      await _secureStorage.deleteRefreshToken();
      await _clearSession();
      return null;
    } on Failure {
      // Anything else (NetworkFailure: no connectivity, or the server
      // genuinely unreachable right now) says nothing about whether the
      // refresh token itself is valid — deliberately NOT deleted. No
      // NEW session is established this launch (no access token exists
      // to attach to a request right now), but the stored refresh token
      // survives so ApiClient's own reactive 401-refresh (already built
      // into the auth interceptor) can succeed with it later, the
      // moment connectivity actually returns and the sync engine's own
      // triggers attempt a real request — exactly Phase 0's own exit
      // criterion (offline create -> restart -> reconnect).
      //
      // This is the actual fix for the gap this whole method used to
      // have: "who's logged in" used to just be null for the entire
      // launch whenever this branch was hit, even though a perfectly
      // valid (if not freshly re-confirmed) identity was sitting right
      // there in the local Sessions table the whole time. Falls back to
      // it now instead of returning null outright — offline-available
      // session info, which is the entire reason this table exists
      // (Section 4 item 4's own framing: "'who's logged in' only lives
      // in an in-memory field, lost on restart until restoreSession()'s
      // network call resolves" — it no longer has to wait for that).
      _currentUser = await _readCachedSession();
      return _currentUser;
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
    await _clearSession();
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
    await _persistSession(_currentUser!);
  }

  /// Writes the signed-in user to the local Sessions table — called on
  /// every successful login and every successful silent refresh, so the
  /// cached copy restoreSession() falls back to on a later offline
  /// launch is never staler than the last time this device actually
  /// talked to the server.
  ///
  /// Deletes every existing row first, unconditionally, then inserts the
  /// fresh one — enforcing "one phone, one signed-in user at a time"
  /// (this table's own doc comment) even for the edge case that actually
  /// matters: a different user signing in without an intervening clean
  /// logout (app force-closed, secure storage cleared by the OS, etc.).
  /// A more surgical "delete every OTHER user's row, upsert this one"
  /// would also preserve activeLocationId across a routine same-user
  /// token refresh — a real advantage, but one bought by relying on a
  /// negated-equality query (`.not()` on an Expression<bool>) with no
  /// precedent anywhere else in this codebase to check the exact API
  /// against, and no working Dart toolchain here to confirm it compiles.
  /// Not worth that risk for a column nothing reads or writes yet
  /// anyway — no location-switcher UI exists (Phase 2). Worth
  /// revisiting when that UI actually gets built, since at that point
  /// resetting activeLocationId on every silent refresh would start
  /// being a real, user-visible cost rather than a theoretical one.
  Future<void> _persistSession(AuthUser user) async {
    await _db.transaction(() async {
      await _db.delete(_db.sessions).go();
      await _db.into(_db.sessions).insert(
            SessionsCompanion.insert(
              userId: user.id,
              username: user.username,
              email: user.email,
              fullName: user.fullName,
              backendRole: user.role,
              isActive: user.isActive,
              lastSyncedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  /// Full clear — called on logout and on a genuinely-invalid refresh
  /// token (AuthFailure in restoreSession above). Functionally the same
  /// unconditional delete _persistSession also does before writing a
  /// fresh row — kept as its own named method rather than reused
  /// directly, since the two call sites mean different things
  /// ("no one should appear signed in on this device at all" here,
  /// vs. "about to write the one row that should exist" there), even
  /// though the SQL is identical today.
  Future<void> _clearSession() async {
    await _db.delete(_db.sessions).go();
  }

  /// Reconstructs the signed-in user from the local Sessions table with
  /// no network involved at all — restoreSession's fallback when the
  /// server is unreachable but a previously-confirmed session is cached.
  /// getSingleOrNull() (not getSingle(), not just taking the first row of
  /// a list) is deliberate: this table is supposed to hold at most one
  /// row (its own "one phone, one signed-in user at a time" doc
  /// comment), which _persistSession's unconditional delete-then-insert
  /// enforces on every write — if this ever throws instead, that
  /// invariant was violated by something bypassing _persistSession
  /// entirely (a raw write elsewhere, a concurrent write racing outside
  /// its transaction), and throwing loudly here is more honest than
  /// silently picking one of several rows and hiding that.
  Future<AuthUser?> _readCachedSession() async {
    final row = await _db.select(_db.sessions).getSingleOrNull();
    if (row == null) return null;
    return AuthUser(
      id: row.userId,
      username: row.username,
      email: row.email,
      fullName: row.fullName,
      role: row.backendRole,
      isActive: row.isActive,
    );
  }
}
