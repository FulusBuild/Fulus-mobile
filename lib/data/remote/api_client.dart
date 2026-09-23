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
    dio.interceptors.addAll([
      _authInterceptor,
      _RetryInterceptor(dio: dio),
    ]);
  }

  final Dio dio;
  final SecureStorage _secureStorage;
  late final _AuthInterceptor _authInterceptor;
  String? _serverAccessToken;

  void configureServerAuth({
    required String supabaseUrl,
    required String publishableKey,
  }) {
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

  String? get serverAccessToken => _serverAccessToken;

  Future<String?> secureRefreshToken() => _secureStorage.getRefreshToken();

  Future<void> clearServerRefreshToken() =>
      _secureStorage.deleteRefreshToken();

  /// Restores the durable Supabase session through the same single-flight
  /// refresh authority used by 401 recovery. Startup and in-flight requests
  /// therefore can never race the one-use refresh-token rotation.
  Future<Map<String, dynamic>?> restoreServerSession({
    required String supabaseUrl,
    required String publishableKey,
  }) => _authInterceptor.restoreServerSession(
        supabaseUrl: supabaseUrl,
        publishableKey: publishableKey,
      );

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
      return const BusinessRuleFailure('Email or password is incorrect.');
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
  String? _supabaseUrl;
  String? _publishableKey;
  Future<_RefreshResult>? _refreshRun;

  void configureServerAuth({
    required String supabaseUrl,
    required String publishableKey,
  }) {
    _supabaseUrl = supabaseUrl;
    _publishableKey = publishableKey;
  }

  void setAccessToken(String? token) => _accessToken = token;

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
        await _expireSession();
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

    final run = _performStoredRefresh();
    late Future<_RefreshResult> tracked;
    tracked = run.whenComplete(() {
      if (identical(_refreshRun, tracked)) _refreshRun = null;
    });
    _refreshRun = tracked;
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
        await _expireSession();
      }
      return null;
    } finally {
      _supabaseUrl = previousUrl;
      _publishableKey = previousKey;
    }
  }

  Future<_RefreshResult> _performStoredRefresh() async {
    final refreshToken = await _secureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const _NoStoredRefreshToken();
    }

    final supabaseUrl = _supabaseUrl ?? SupabaseConfig.url;
    final publishableKey = _publishableKey ?? SupabaseConfig.publishableKey;
    final refreshClient = Dio(BaseOptions(
      baseUrl: supabaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    final response = await refreshClient.post(
      '/auth/v1/token?grant_type=refresh_token',
      data: {'refresh_token': refreshToken},
      options: Options(headers: {
        'apikey': publishableKey,
        'content-type': 'application/json',
      }),
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    final newAccessToken = data['access_token'] as String?;
    final newRefreshToken = data['refresh_token'] as String?;
    if (newAccessToken == null || newAccessToken.isEmpty) {
      throw StateError('Supabase refresh returned no access token.');
    }

    setAccessToken(newAccessToken);
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      await _secureStorage.setRefreshToken(newRefreshToken);
    }
    return _RefreshResult(
      accessToken: newAccessToken,
      raw: data,
    );
  }

  bool _isRefreshTokenRejected(DioException error) {
    final status = error.response?.statusCode;
    return status == 400 || status == 401;
  }

  Future<void> _expireSession() async {
    await _secureStorage.deleteRefreshToken();
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
    final isRetryable = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (status != null && status >= 500);
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
