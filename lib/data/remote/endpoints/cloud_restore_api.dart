import 'package:dio/dio.dart';

import '../../../core/config/supabase_config.dart';
import '../api_client.dart';

/// Fetches the authenticated user's complete business restore snapshot.
///
/// Restore is a Supabase Edge Function, so it must use the Supabase project
/// URL directly rather than the legacy API base URL used by ordinary app APIs.
class CloudRestoreApi {
  CloudRestoreApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchSnapshot({required String businessId}) async {
    final accessToken = _client.serverAccessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Fulus Cloud session is missing. Please sign in again.');
    }

    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: SupabaseConfig.url,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      ).post(
        '/functions/v1/fulus-restore',
        data: {'business_id': businessId},
        options: Options(
          headers: {
            'apikey': SupabaseConfig.publishableKey,
            'Authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
        ),
      );

      final root = response.data;
      if (root is! Map) {
        throw const FormatException('Fulus Cloud returned an invalid restore response.');
      }
      final data = root['data'];
      if (data is! Map) {
        final error = root['error'];
        final message = error is Map ? error['message']?.toString() : null;
        throw FormatException(
          message == null || message.isEmpty
              ? 'Fulus Cloud did not return a restore snapshot.'
              : message,
        );
      }
      return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
