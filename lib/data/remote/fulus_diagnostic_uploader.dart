import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import '../../core/diagnostics/diagnostic_logger.dart';
import '../../core/diagnostics/models/diagnostic_event.dart';
import 'api_client.dart';
import 'fulus_connection_state.dart';

/// Best-effort bridge from the existing on-device Diagnostics system to the
/// remote diagnostic store. It never participates in the business operation
/// itself: network failures are swallowed so diagnostics can never become a
/// new application failure.
///
/// The local DiagnosticLogger remains the source of truth. Events are retried
/// on subsequent flushes, including events captured before authentication;
/// once a valid server session exists they become remotely inspectable.
class FulusDiagnosticUploader {
  FulusDiagnosticUploader({
    required DiagnosticLogger logger,
    required ApiClient apiClient,
    required FulusConnectionState connection,
    Duration interval = const Duration(seconds: 15),
  })  : _logger = logger,
        _apiClient = apiClient,
        _connection = connection,
        _interval = interval;

  final DiagnosticLogger _logger;
  final ApiClient _apiClient;
  final FulusConnectionState _connection;
  final Duration _interval;
  final Set<String> _uploadedIds = <String>{};
  Timer? _timer;
  bool _running = false;

  void start() {
    if (_timer != null) return;
    unawaited(flush());
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> flush() async {
    if (_running) return;
    final token = _apiClient.serverAccessToken;
    if (token == null || token.isEmpty) return;

    _running = true;
    try {
      final events = await _logger.getForExport();
      for (final event in events) {
        if (_uploadedIds.contains(event.id)) continue;
        final accepted = await _upload(event, token);
        if (accepted) _uploadedIds.add(event.id);
      }
    } catch (_) {
      // Remote diagnostics is strictly best-effort. The local diagnostic
      // store/fallback remains authoritative when the network is unavailable.
    } finally {
      _running = false;
    }
  }

  Future<bool> _upload(DiagnosticEvent event, String token) async {
    try {
      final response = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 12),
        validateStatus: (_) => true,
      )).post(
        '${SupabaseConfig.url}/functions/v1/fulus-diagnostics',
        data: {
          'business_id': _connection.selectedBusinessId,
          'device_client_id': _connection.registeredDevice?.deviceClientId,
          'event': event.toJson(),
        },
        options: Options(headers: {
          'content-type': 'application/json',
          'Authorization': 'Bearer $token',
          if (_connection.registeredDevice?.deviceClientId != null)
            'x-fulus-device-id': _connection.registeredDevice!.deviceClientId,
        }),
      );
      final status = response.statusCode ?? 0;
      return status >= 200 && status < 300;
    } catch (_) {
      return false;
    }
  }
}
