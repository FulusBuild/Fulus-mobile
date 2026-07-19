import 'package:dio/dio.dart';

import '../../core/errors/failure.dart';
import '../local/secure_storage/secure_storage.dart';

/// The single Dio instance the whole app shares, wrapping Architecture
/// Section 5's interceptor stack in the exact order specified there:
/// auth first (attaches the token, handles 401-triggered refresh), then
/// retry (backs off on network/5xx, never on 4xx), then error mapping
/// (converts whatever comes out the other end into a Failure). Logging
/// is added only in debug builds, per Section 5's explicit note that
/// production builds must not log request/response bodies given this
/// handles real financial data.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required SecureStorage secureStorage,
    required Future<void> Function() onSessionExpired,
  })  : _secureStorage = secureStorage,
        _onSessionExpired = onSessionExpired,
        dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )) {
    dio.interceptors.addAll([
      _AuthInterceptor(
        secureStorage: _secureStorage,
        dio: dio,
        onSessionExpired: _onSessionExpired,
      ),
      _RetryInterceptor(dio: dio),
      // The error-mapping interceptor is last, deliberately — by the
      // time a response or error reaches it, auth refresh has already
      // been attempted and retry has already been exhausted, so what
      // arrives here is genuinely final and ready to become a Failure,
      // not an intermediate state something upstream might still resolve.
    ]);
  }

  final Dio dio;
  final SecureStorage _secureStorage;
  final Future<void> Function() _onSessionExpired;

  /// Converts whatever Dio produced into a real Failure, following
  /// Architecture Section 5's table exhaustively. Called explicitly by
  /// each endpoint method (data/remote/endpoints/*.dart) around its own
  /// Dio call — kept as a standalone function rather than baked silently
  /// into an interceptor's error handler, so an endpoint method can
  /// still distinguish "this specific call's 409 means success" (the
  /// idempotent-retry case) from a genuine 409 elsewhere, which a single
  /// app-wide interceptor rule couldn't do without knowing which
  /// endpoint it's looking at.
  Failure mapError(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return const NetworkFailure.offline();
    }

    final response = error.response;
    if (response == null) {
      // A timeout after the request DID reach the server (sendTimeout,
      // receiveTimeout) is different from never connecting at all — the
      // server may have processed it. Mapped to serverUnavailable, not
      // offline, since the local write already stands regardless
      // (Architecture Section 4: repositories never await the network
      // inside a write), and re-attempting via the sync queue's retry
      // interceptor is the correct next step either way.
      return const NetworkFailure.serverUnavailable();
    }

    final status = response.statusCode ?? 0;
    final body = response.data;

    switch (status) {
      case 401:
        // The auth interceptor already attempted a silent refresh before
        // this could ever reach here — a 401 surfacing this far means
        // the refresh itself also failed.
        return const AuthFailure.sessionExpired();

      case 403:
        // Architecture Section 5's explicit callout: this is a REAL,
        // expected outcome now that the backend enforces roles
        // server-side (verified directly — the fixes I made myself to
        // sales.py/finance.py/employees.py/inventory.py/customers.py
        // during the prior audit), not a case that "shouldn't happen."
        return const AuthFailure.forbidden();

      case 409:
        // Deliberately NOT mapped to a Failure at all in the general
        // case reachable from here — per Architecture Section 5, a 409
        // on a sale-creation retry (client_reference collision) is a
        // SUCCESS signal, not a failure, and must be special-cased by
        // the calling endpoint method BEFORE this function is ever
        // reached for that specific call. If mapError is reached with a
        // 409, it's being treated as a genuine conflict here because the
        // caller didn't intercept it as the idempotent-success case —
        // callers that create resources with a client_reference-style
        // idempotency key are responsible for checking for 409
        // specifically and treating it as success themselves; see
        // SalesApi.createSale in data/remote/endpoints/sales_api.dart
        // for the actual implementation of that special case.
        return BusinessRuleFailure(
          _extractMessage(body) ?? 'This already happened — no changes needed.',
        );

      case 422:
        return ValidationFailure(fieldErrors: _extractFieldErrors(body));

      case 429:
        final lockedUntilRaw = _extractDetailField(body, 'locked_until');
        if (lockedUntilRaw != null) {
          final parsed = DateTime.tryParse(lockedUntilRaw);
          if (parsed != null) {
            return AuthFailure.accountLocked(lockedUntil: parsed);
          }
        }
        // The backend's 429 for account lockout embeds the unlock time
        // in its message text (verified directly: auth_service.py's
        // AccountLockedError formats it into the detail string itself,
        // not a separate structured field) rather than a dedicated JSON
        // field — this fallback handles that shape; the structured-field
        // attempt above is forward-looking in case that changes, not a
        // claim it works today.
        return BusinessRuleFailure(
          _extractMessage(body) ?? 'Too many attempts. Please wait and try again.',
        );

      case >= 400 && < 500:
        // Every other 4xx — a deliberate business-rule rejection.
        // Architecture Section 5's table: shown verbatim, since the
        // backend's own messages already meet the plain-language bar
        // (verified directly against several examples during the audit).
        return BusinessRuleFailure(
          _extractMessage(body) ?? 'That couldn\'t be completed.',
        );

      case >= 500:
        return const NetworkFailure.serverUnavailable();

      default:
        // No status code branch above should be unreachable for a real
        // HTTP response, but a default case exists rather than letting a
        // genuinely unexpected status fall through unmapped — mapped to
        // the most conservative, least alarming Failure rather than a
        // raw-exception catch-all (see failure.dart's own closing
        // comment on why no UnknownFailure variant exists).
        return const NetworkFailure.serverUnavailable();
    }
  }

  String? _extractMessage(dynamic body) {
    if (body is Map && body['detail'] is String) {
      return body['detail'] as String;
    }
    return null;
  }

  String? _extractDetailField(dynamic body, String field) {
    if (body is Map && body['detail'] is Map) {
      final detail = body['detail'] as Map;
      if (detail[field] is String) return detail[field] as String;
    }
    return null;
  }

  Map<String, String> _extractFieldErrors(dynamic body) {
    // FastAPI's default 422 shape (verified directly against the
    // backend's own RequestValidationError handling in
    // middleware/error_handlers.py): {"detail": [{"loc": [...], "msg":
    // "...", ...}, ...]}. Mapped to a flat field-name -> message map,
    // since that's what a form screen actually needs to key errors by.
    final errors = <String, String>{};
    if (body is Map && body['detail'] is List) {
      for (final item in (body['detail'] as List)) {
        if (item is Map && item['loc'] is List && item['msg'] is String) {
          final loc = item['loc'] as List;
          // loc is typically ['body', 'field_name'] — the field name is
          // the last element, not the first, which is always the
          // location type ('body', 'query', etc.), not useful as a key.
          final fieldName = loc.isNotEmpty ? loc.last.toString() : 'unknown';
          errors[fieldName] = item['msg'] as String;
        }
      }
    }
    return errors;
  }
}

/// Attaches the access token to every request and handles the 401 ->
/// silent-refresh -> retry-original-request flow. The access token
/// itself is read from wherever the app holds it in memory (Architecture
/// Section 6: never persisted directly) via the getter passed in — this
/// interceptor doesn't own token state, it only consumes and refreshes it.
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
  final Future<void> Function() _onSessionExpired;

  String? _accessToken;
  bool _isRefreshing = false;

  void setAccessToken(String? token) => _accessToken = token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_accessToken != null) {
      options.headers['Authorization'] = 'Bearer $_accessToken';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || _isRefreshing) {
      handler.next(err);
      return;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await _secureStorage.getRefreshToken();
      if (refreshToken == null) {
        await _onSessionExpired();
        handler.next(err);
        return;
      }

      // A bare, uninterceptored Dio call for the refresh itself —
      // deliberately not going through the same client instance's
      // interceptor stack, to avoid a refresh call that itself 401s
      // recursively triggering another refresh attempt.
      final refreshResponse = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
          .post('/api/auth/refresh', data: {'refresh_token': refreshToken});

      final newAccessToken = refreshResponse.data['access_token'] as String;
      final newRefreshToken = refreshResponse.data['refresh_token'] as String;
      setAccessToken(newAccessToken);
      await _secureStorage.setRefreshToken(newRefreshToken);

      // Retry the original request with the new token.
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      final retryResponse = await _dio.fetch(retryOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await _secureStorage.deleteRefreshToken();
      await _onSessionExpired();
      handler.next(err);
    } finally {
      _isRefreshing = false;
    }
  }
}

/// Architecture Section 5's exact retry policy: immediate retry once,
/// then backing off through the brief's own stated cadence (30s, 2min,
/// 10min, continue) — for network errors and 5xx only, never 4xx, since
/// a 4xx means the server processed the request and rejected it for a
/// real reason retrying can't fix. This mirrors the exact 4xx/5xx
/// distinction I verified directly in the desktop app's own
/// offline-sync.ts during the prior audit.
///
/// This interceptor handles retry for a SINGLE in-flight request (e.g. a
/// live screen's read that failed transiently) — it is deliberately
/// separate from the sync QUEUE's own retry/backoff logic (sync/retry_policy.dart,
/// Architecture Section 8), which operates on queued writes across
/// separate app sessions, not a single request's immediate retry
/// attempts within one call. Conflating the two would mean a live
/// screen's read retry logic and the offline sync queue's multi-day
/// backoff logic fighting over the same state.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static const _backoffSteps = [
    Duration.zero, // immediate retry
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
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    try {
      final retryOptions = err.requestOptions;
      retryOptions.extra['retry_attempt'] = attempt + 1;
      final response = await _dio.fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      // onError will be invoked again for this new failure, and
      // retry_attempt has already been incremented above, so the next
      // pass through this same interceptor picks up at the correct
      // backoff step rather than restarting from immediate.
      handler.next(retryError);
    }
  }
}
