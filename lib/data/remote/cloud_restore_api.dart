import 'package:dio/dio.dart';

import '../../core/errors/failure.dart';
import 'api_client.dart';

/// Fetches the authoritative cloud snapshot used for stale-cursor recovery.
class CloudRestoreApi {
  CloudRestoreApi({required ApiClient client, required String functionBaseUrl})
      : _client = client,
        _functionBaseUrl = functionBaseUrl;

  final ApiClient _client;
  final String _functionBaseUrl;

  Future<Map<String, dynamic>> fetchSnapshot({
    required String businessId,
  }) async {
    final response = await _client.dio.post(
      _functionBaseUrl,
      data: <String, dynamic>{
        'action': 'restore_snapshot',
        'business_id': businessId,
      },
    );
    final body = response.data;
    if (body is! Map || body['data'] is! Map) {
      throw const FormatException('Cloud restore returned an invalid snapshot response.');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}
