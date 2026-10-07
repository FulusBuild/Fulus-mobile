import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import '../../core/errors/failure.dart';
import '../local/secure_storage/secure_storage.dart';

/// Shared HTTP client for the networked/cloud layer.
///
/// Cloud access tokens are kept in memory. Refresh tokens are kept in secure
/// storage. Supabase is the authority for cloud session refreshes; the client
/// never attempts to refresh a Supabase token through the legacy API.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required SecureStorage secureStorage,
    required Future<void> Function() onSessionExpired,
    bool enableGenericRetry = true,
  })  : _secureStorage = secureStorage,
        dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )) {
    _authInterceptor = _AuthInterceptor(
      secureStorage: _secureStorage,
      dio: dio,
      onSessionExpired: onSessionExpired,
    );
    dio.interceptors.add(_authInterceptor);
    if (enableGenericRetry) {
      dio.interceptors.add(_RetryInterceptor(dio: dio));
    }
  }

  final Dio dio;
  final SecureStorage _secureStorage;
  late final _AuthInterceptor _authInterceptor;
  String? _serverAccessToken;
  String? _activeCloudUserId;
  String? _supabaseUrl;
  String? _publishableKey;
  final Map<String, Future<String?>> _scopedRefreshRuns = {};
  final Map<String, _ScopedAccessToken> _scopedAccessTokens = {};

  void configureServerAuth({
    required String supabaseUrl,
    required String publishableKey,
  }) {
    _supabaseUrl = supabaseUrl;
    _publishableKey = publishableKey;
    _authInterceptor.configureServerAuth(
      supabaseUrl: supabaseUrl,
      publishableKey: publishableKey,
    );
  }

  void setAccessToken(String? token) {
    _authInterceptor.setAccessToken(token);
    _serverAccessToken = token;
  }

  Future<void> setServerAccessToken(String token) async {
    _authInterceptor.setAccessToken(token);
    _serverAccessToken = token;
  }

  Future<void> persistServerRefreshToken(String token) =>
      _secureStorage.setRefreshToken(token);

  Future<void> persistServerRefreshTokenForUser({
    required String userId,
    required String token,
  }) =>
      _secureStorage.setUserRefreshToken(userId, token);

  void setActiveCloudUser(String? userId) {
    _activeCloudUserId = userId;
    _authInterceptor.setActiveCloudUser(userId);
  }

  String? get activeCloudUserId => _activeCloudUserId;

  String? get serverAccessToken => _serverAccessToken;

  Future<String?> secureRefreshToken() => _secureStorage.getRefreshToken();

  Future<void> clearServerRefreshToken() =>
      _secureStorage.deleteRefreshToken();

  Future<void> clearActiveCloudSession() async {
    _activeCloudUserId = null;
    setAccessToken(null);
    await _secureStorage.deleteRefreshToken();
  }

  Future<String?> accessTokenForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        userId == _activeCloudUserId &&
        _serverAccessToken != null &&
        _serverAccessToken!.isNotEmpty) {
      return _serverAccessToken;
    }
    if (!forceRefresh) {
      final cached = _scopedAccessTokens[userId];
      if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
        return cached.token;
      }
    }
    final existing = _scopedRefreshRuns[userId];
    if (existing != null) return existing;
    final run = _refreshUserAccessToken(userId);
    _scopedRefreshRuns[userId] = run;
    try {
      return await run;
    } finally {
      _scopedRefreshRuns.remove(userId);
    }
  }

  Future<String?> _refreshUserAccessToken(String userId) async {
    final supabaseUrl = _supabaseUrl;
    final publishableKey = _publishableKey;
    if (supabaseUrl == null || publishableKey == null) {
      throw StateError('Supabase auth is not configured.');
    }
    final refreshToken = await _secureStorage.getUserRefreshToken(userId);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final refreshClient = Dio(BaseOptions(
      baseUrl: supabaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      final response = await refreshClient.post(
        '/auth/v1/token?grant_type=refresh_token',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {
            'apikey': publishableKey,
            'content-type': 'application/json',
          },
        ),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['access_token'] as String?;
      final rotatedRefreshToken = data['refresh_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('Supabase refresh returned no access token.');
      }
      if (rotatedRefreshToken != null && rotatedRefreshToken.isNotEmpty) {
        await _secureStorage.setUserRefreshToken(userId, rotatedRefreshToken);
      }
      _scopedAccessTokens[userId] = _ScopedAccessToken(
        token: accessToken,
        expiresAt: DateTime.now().add(
          Duration(seconds: expiresIn > 30 ? expiresIn - 30 : expiresIn),
        ),
      );
      return accessToken;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401) {
        await _secureStorage.deleteUserRefreshToken(userId);
      }
      return null;
    }
  }

  Future<String?> deviceClientId() => _secureStorage.getDeviceClientId();

  Future<Map<String, dynamic>?> restoreServerSessionForUser({
    required String userId,
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final refreshToken = await _secureStorage.getUserRefreshToken(userId);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    // Do not change the active cloud identity until the refresh succeeds.
    // A failed refresh must never leave the previous employee's access token
    // paired with the target employee id on this shared device.
    final refreshClient = Dio(BaseOptions(
      baseUrl: supabaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      final response = await refreshClient.post(
        '/auth/v1/token?grant_type=refresh_token',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {
            'apikey': publishableKey,
            'content-type': 'application/json',
          },
          extra: {'skip_generic_retry': true},
        ),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['access_token'] as String?;
      final rotatedRefreshToken = data['refresh_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw StateError('Supabase refresh returned no access token.');
      }
      final responseUserId =
          (data['user'] is Map) ? (data['user'] as Map)['id']?.toString() : null;
      if (responseUserId != userId) {
        // Do not ever pair a target local identity with a token issued for a
        // different Supabase user.
        return null;
      }
      if (rotatedRefreshToken != null && rotatedRefreshToken.isNotEmpty) {
        await _secureStorage.setUserRefreshToken(userId, rotatedRefreshToken);
        // Keep the compatibility/global copy in lockstep with the active
        // cloud identity. Startup may still use that copy before the cloud
        // user id is known.
        await _secureStorage.setRefreshToken(rotatedRefreshToken);
      }
      // Commit the in-memory cloud identity only after Supabase accepted the
      // target employee's refresh token and returned the same cloud identity.
      _activeCloudUserId = userId;
      _authInterceptor.setActiveCloudUser(userId);
      setAccessToken(accessToken);
      return data;
    } on DioException catch (error) {
      if (error.response?.statusCode == 400 ||
          error.response?.statusCode == 401) {
        await _secureStorage.deleteUserRefreshToken(userId);
      }
      return null;
    }
  }

  /// Restores the durable Supabase session through the same single-flight
  /// refresh authority used by 401 recovery. Startup and in-flight requests
  /// therefore can never race the one-use refresh-token rotation.
  Future<Map<String, dynamic>?> restoreServerSession({
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final data = await _authInterceptor.restoreServerSession(
      supabaseUrl: supabaseUrl,
      publishableKey: publishableKey,
    );
    final responseUserId =
        (data?['user'] is Map) ? (data!['user'] as Map)['id']?.toString() : null;
    if (responseUserId != null && responseUserId.isNotEmpty) {
      // Startup/global restoration has no local identity key. The Supabase
      // response is the authoritative cloud identity and must be propagated
      // to both ApiClient and its interceptor.
      setActiveCloudUser(responseUserId);
    }
    return data;
  }

  /// Invalidates the active cloud session and notifies the application state
  /// layer. Used by startup refresh when Supabase permanently rejects the
  /// durable refresh token, keeping startup and in-flight 401 expiry on the
  /// same lifecycle path.
  Future<void> expireServerSession() => _authInterceptor.expireSession();

  void setOnSessionExpired(Future<void> Function() callback) =>
      _authInterceptor.setOnSessionExpired(callback);

  Failure mapError(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure.offline();
    }

    final response = error.response;
    if (response == null) return const NetworkFailure.serverUnavailable();

    final status = response.statusCode ?? 0;
    final body = response.data;
    final code = _extractCode(body);
    final message = _extractMessage(body);

    if (status == 401) return const AuthFailure.sessionExpired();
    if (status == 403) {
      if (code == 'DEVICE_NOT_REGISTERED') {
        return const AuthFailure.deviceNotRegistered();
      }
      if (code == 'NOT_ACTIVE_MEMBER') {
        return const AuthFailure.accessRevoked();
      }
      return const AuthFailure.forbidden();
    }

    if (code == 'email_not_confirmed' || code == 'phone_not_confirmed') {
      return BusinessRuleFailure(
        code == 'phone_not_confirmed'
            ? 'Please verify your phone number before signing in.'
            : 'Please verify your email before signing in.',
      );
    }
    if (code == 'invalid_credentials' ||
        code == 'user_not_found' ||
        code == 'email_exists') {
      return BusinessRuleFailure(
        'Email or password is incorrect.',
        code: code,
      );
    }
    if (code == 'signup_disabled' || code == 'email_provider_disabled') {
      return const BusinessRuleFailure(
        'New cloud accounts are currently unavailable. Please try again later.',
      );
    }
    if (code == 'weak_password') {
      return BusinessRuleFailure(
        message ?? 'Choose a stronger password and try again.',
      );
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit') {
      return const BusinessRuleFailure(
        'Too many requests. Please wait a little and try again.',
      );
    }
    if (code == 'refresh_token_already_used' ||
        code == 'refresh_token_not_found' ||
        code == 'session_expired' ||
        code == 'session_not_found') {
      return const AuthFailure.sessionExpired();
    }

    if (status == 410 && code == 'SYNC_CURSOR_TOO_OLD') {
      return BusinessRuleFailure(
        message ?? 'Cloud history is too old for incremental sync. A fresh reconciliation is required.',
        code: code,
      );
    }
    if (code == 'BUSINESS_PROVISIONING_UNAVAILABLE') {
      return BusinessRuleFailure(
        message ?? 'Business setup is temporarily unavailable. Please try again.',
        code: code,
      );
    }
    if (code == 'BUSINESS_ALREADY_LINKED') {
      return BusinessRuleFailure(
        message ?? 'This account is already linked to a Fulus business. Sign in to continue.',
        code: code,
      );
    }

    switch (status) {
      case 409:
        return BusinessRuleFailure(
          message ?? 'This operation conflicts with existing data.',
          code: code,
        );
      case 422:
        return ValidationFailure(fieldErrors: _extractFieldErrors(body));
      case 429:
        final lockedUntilRaw = _extractDetailField(body, 'locked_until');
        final parsed = lockedUntilRaw == null
            ? null
            : DateTime.tryParse(lockedUntilRaw);
        if (parsed != null) return AuthFailure.accountLocked(lockedUntil: parsed);
        return BusinessRuleFailure(
          message ?? 'Too many attempts. Please wait and try again.',
          code: code,
        );
      case >= 400 && < 500:
        return BusinessRuleFailure(message ?? 'That couldn\'t be completed.', code: code);
      case >= 500:
        return const NetworkFailure.serverUnavailable();
      default:
        return const NetworkFailure.serverUnavailable();
    }
  }

  String? _extractCode(dynamic body) {
    if (body is! Map) return null;
    final direct = body['code'];
    if (direct is String && direct.isNotEmpty) return direct;
    final error = body['error'];
    if (error is Map && error['code'] is String) return error['code'] as String;
    return null;
  }

  String? _extractMessage(dynamic body) {
    if (body is! Map) return null;
    for (final key in ['message', 'msg', 'error_description', 'detail']) {
      final value = body[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    final error = body['error'];
    if (error is Map) {
      for (final key in ['message', 'msg', 'error_description', 'detail']) {
        final value = error[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  String? _extractDetailField(dynamic body, String field) {
    if (body is! Map || body['detail'] is! Map) return null;
    final detail = body['detail'] as Map;
    return detail[field] is String ? detail[field] as String : null;
  }

  Map<String, String> _extractFieldErrors(dynamic body) {
    final errors = <String, String>{};
    if (body is Map && body['detail'] is List) {
      for (final item in body['detail'] as List) {
        if (item is Map && item['loc'] is List && item['msg'] is String) {
          final loc = item['loc'] as List;
          final fieldName = loc.isNotEmpty ? loc.last.toString() : 'unknown';
          errors[fieldName] = item['msg'] as String;
        }
      }
    }
    return errors;
  }
}


class _ScopedAccessToken {
  const _ScopedAccessToken({
    required this.token,
    required this.expiresAt,
  });

  final String token;
  final DateTime expiresAt;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor({
    required SecureStorage secureStorage,
    required Dio dio,
    required Future<void> Function() onSessionExpired,
  })  : _secureStorage = secureStorage,
        _dio = dio,
        _onSessionExpired = onSessionExpired;

  final SecureStorage _secureStorage;
  final Dio _dio;
  Future<void> Function() _onSessionExpired;
  String? _accessToken;
  String? _activeCloudUserId;
  String? _supabaseUrl;
  String? _publishableKey;
  Future<_RefreshResult>? _refreshRun;
  String? _refreshTokenUsedForCurrentRun;

  void configureServerAuth({
    required String supabaseUrl,
    required String publishableKey,
  }) {
    _supabaseUrl = supabaseUrl;
    _publishableKey = publishableKey;
  }

  void setAccessToken(String? token) => _accessToken = token;
  void setActiveCloudUser(String? userId) => _activeCloudUserId = userId;


  void setOnSessionExpired(Future<void> Function() callback) =>
      _onSessionExpired = callback;

  Future<void> _attachHeaders(RequestOptions options) async {
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    final deviceClientId = await _secureStorage.getDeviceClientId();
    if (deviceClientId != null && deviceClientId.isNotEmpty) {
      options.headers['x-fulus-device-id'] = deviceClientId;
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      await _attachHeaders(options);
      handler.next(options);
    } catch (_) {
      handler.next(options);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // A request that has already been retried with a refreshed token must not
    // start an unbounded refresh/retry loop. At this point the new token was
    // accepted by Supabase, but the API still rejected this request.
    if (err.requestOptions.extra['auth_refresh_attempted'] == true) {
      await _expireSession();
      handler.next(err);
      return;
    }

    // Another request may have completed the shared refresh between the
    // time this request received its 401 and this interceptor running. In
    // that case the request's token is stale, so replay it with the already
    // refreshed token instead of rotating the one-use refresh token again.
    final currentAccessToken = _accessToken;
    final requestAuthorization =
        err.requestOptions.headers['Authorization']?.toString();
    if (currentAccessToken != null &&
        currentAccessToken.isNotEmpty &&
        requestAuthorization != 'Bearer $currentAccessToken') {
      try {
        final retryOptions = err.requestOptions;
        retryOptions.extra['auth_refresh_attempted'] = true;
        retryOptions.headers['Authorization'] = 'Bearer $currentAccessToken';
        final retryResponse = await _dio.fetch(retryOptions);
        handler.resolve(retryResponse);
      } on DioException catch (retryError) {
        if (retryError.response?.statusCode == 401) {
          await _expireSession();
        }
        handler.next(retryError);
      }
      return;
    }

    try {
      final refreshResult = await _refreshAccessToken();
      final accessToken = refreshResult.accessToken;
      final retryOptions = err.requestOptions;
      retryOptions.extra['auth_refresh_attempted'] = true;
      retryOptions.headers['Authorization'] = 'Bearer $accessToken';

      // Keep the refresh transaction separate from the replayed application
      // request. A 400/500 from the application endpoint is not evidence that
      // Supabase rejected the refresh token and must not destroy durable auth.
      try {
        final retryResponse = await _dio.fetch(retryOptions);
        handler.resolve(retryResponse);
      } on DioException catch (retryError) {
        // A second 401 after a successful refresh means the newly refreshed
        // session is not accepted by the API. Other application failures are
        // ordinary request failures and should simply propagate.
        if (retryError.response?.statusCode == 401) {
          await _expireSession();
        }
        handler.next(retryError);
      }
    } on DioException catch (refreshError) {
      // Only an explicit rejection from the Supabase refresh endpoint
      // invalidates the durable refresh token. Network/server failures must
      // preserve it so the next connectivity-triggered recovery can retry.
      if (_isRefreshTokenRejected(refreshError)) {
        await _expireSession(expectedRefreshToken: _refreshTokenUsedForCurrentRun);
      }
      handler.next(refreshError);
    } catch (refreshError) {
      // A malformed refresh response is a local/session failure, not a
      // transient transport failure.
      await _expireSession();
      handler.next(err);
    }
  }

  Future<_RefreshResult> _refreshAccessToken() {
    final active = _refreshRun;
    if (active != null) return active;

    // Install the shared future before starting the asynchronous refresh.
    // _performStoredRefresh() immediately reaches its first await while
    // reading SecureStorage, so assigning the future only after invoking it
    // leaves a real window where another 401/startup restore can start a
    // second one-use refresh-token rotation.
    final completer = Completer<_RefreshResult>();
    final tracked = completer.future;
    _refreshRun = tracked;

    () async {
      try {
        final result = await _performStoredRefresh();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_refreshRun, tracked)) {
          _refreshRun = null;
        }
      }
    }();

    return tracked;
  }

  /// Startup restoration deliberately reads the refresh token inside the
  /// single-flight transaction. A caller can therefore never capture an old
  /// one-use token just before another request rotates it.
  Future<Map<String, dynamic>?> restoreServerSession({
    required String supabaseUrl,
    required String publishableKey,
  }) async {
    final previousUrl = _supabaseUrl;
    final previousKey = _publishableKey;
    _supabaseUrl = supabaseUrl;
    _publishableKey = publishableKey;
    try {
      final refreshResult = await _refreshAccessToken();
      return refreshResult.raw;
    } on _NoStoredRefreshToken {
      return null;
    } on DioException catch (error) {
      if (_isRefreshTokenRejected(error)) {
        await _expireSession(expectedRefreshToken: _refreshTokenUsedForCurrentRun);
      }
      return null;
    } finally {
      _supabaseUrl = previousUrl;
      _publishableKey = previousKey;
    }
  }

  Future<_RefreshResult> _performStoredRefresh() async {
    String? refreshToken;
    var persistAsUser = false;
    if (_activeCloudUserId != null) {
      // Once a cloud identity is explicitly selected, only that identity's
      // durable refresh token is valid. Never fall back to the legacy global
      // token: on a shared device that token may belong to another account,
      // and refreshing it would silently pair the wrong cloud identity with
      // the active local session.
      refreshToken =
          await _secureStorage.getUserRefreshToken(_activeCloudUserId!);
      persistAsUser = true;
    } else {
      // Startup restoration may use the legacy global token. The refresh
      // response establishes the authoritative cloud user id below.
      refreshToken = await _secureStorage.getRefreshToken();
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const _NoStoredRefreshToken();
    }
    _refreshTokenUsedForCurrentRun = refreshToken;
    return _performRefreshToken(
      refreshToken,
      persistAsUser: persistAsUser,
    );
  }

  Future<_RefreshResult> _performRefreshToken(
    String refreshToken, {
    required bool persistAsUser,
    String? supabaseUrl,
    String? publishableKey,
  }) async {
    final refreshClient = Dio(BaseOptions(
      baseUrl: supabaseUrl ?? _supabaseUrl ?? SupabaseConfig.url,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final response = await refreshClient.post(
      '/auth/v1/token?grant_type=refresh_token',
      data: {'refresh_token': refreshToken},
      options: Options(
        headers: {
          'apikey': publishableKey ?? _publishableKey ?? SupabaseConfig.publishableKey,
          'content-type': 'application/json',
        },
        extra: {'skip_generic_retry': true},
      ),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final newAccessToken = data['access_token'] as String?;
    final newRefreshToken = data['refresh_token'] as String?;
    final responseUserId =
        (data['user'] is Map) ? (data['user'] as Map)['id']?.toString() : null;
    if (newAccessToken == null || newAccessToken.isEmpty) {
      throw StateError('Supabase refresh returned no access token.');
    }

    if (persistAsUser) {
      final expectedUserId = _activeCloudUserId;
      if (expectedUserId == null ||
          responseUserId == null ||
          responseUserId.isEmpty ||
          responseUserId != expectedUserId) {
        throw StateError(
          'Supabase refresh returned a different cloud identity than the active user.',
        );
      }
    } else if (responseUserId != null && responseUserId.isNotEmpty) {
      // The legacy/global startup credential has no local identity key.
      // Bind the active cloud identity only to the identity returned by
      // Supabase, never to the local Users-table id.
      setActiveCloudUser(responseUserId);
    }

    setAccessToken(newAccessToken);
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      // Supabase rotates refresh tokens. The app historically kept both a
      // global token and a per-user token, so updating only one copy leaves
      // the other copy stale. The next restore path then receives
      // refresh_token_already_used even though the user's password/session
      // is valid. Keep both copies synchronized to the same current cloud
      // identity while this compatibility path remains in use.
      if (responseUserId != null && responseUserId.isNotEmpty) {
        await _secureStorage.setRefreshToken(newRefreshToken);
        await _secureStorage.setUserRefreshToken(
          responseUserId,
          newRefreshToken,
        );
      } else if (persistAsUser && _activeCloudUserId != null) {
        await _secureStorage.setUserRefreshToken(
          _activeCloudUserId!,
          newRefreshToken,
        );
        await _secureStorage.setRefreshToken(newRefreshToken);
      } else {
        await _secureStorage.setRefreshToken(newRefreshToken);
      }
    }
    return _RefreshResult(accessToken: newAccessToken, raw: data);
  }

  bool _isRefreshTokenRejected(DioException error) {
    final status = error.response?.statusCode;
    return status == 400 || status == 401;
  }

  Future<void> _expireSession({String? expectedRefreshToken}) async {
    if (expectedRefreshToken == null) {
      await _secureStorage.deleteRefreshToken();
      if (_activeCloudUserId != null) {
        await _secureStorage.deleteUserRefreshToken(_activeCloudUserId!);
      }
    } else {
      await _secureStorage.deleteRefreshTokenIfMatches(expectedRefreshToken);
      if (_activeCloudUserId != null) {
        await _secureStorage.deleteUserRefreshTokenIfMatches(
          _activeCloudUserId!,
          expectedRefreshToken,
        );
      }
    }
    setAccessToken(null);
    await _onSessionExpired();
  }

  Future<void> expireSession() => _expireSession();
}

class _RefreshResult {
  const _RefreshResult({
    required this.accessToken,
    required this.raw,
  });

  final String accessToken;
  final Map<String, dynamic> raw;
}

class _NoStoredRefreshToken implements Exception {
  const _NoStoredRefreshToken();
}

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({required Dio dio}) : _dio = dio;

  final Dio _dio;
  static const _backoffSteps = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final isRetryable = err.requestOptions.extra['skip_generic_retry'] != true &&
        (err.type == DioExceptionType.connectionError ||
            err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            (status != null && status >= 500));
    final attempt = (err.requestOptions.extra['retry_attempt'] as int?) ?? 0;

    if (!isRetryable || attempt >= _backoffSteps.length) {
      handler.next(err);
      return;
    }

    final delay = _backoffSteps[attempt];
    if (delay > Duration.zero) await Future.delayed(delay);

    try {
      final retryOptions = err.requestOptions;
      retryOptions.extra['retry_attempt'] = attempt + 1;
      final response = await _dio.fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
