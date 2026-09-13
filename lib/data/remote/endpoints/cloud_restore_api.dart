import 'package:dio/dio.dart';

import '../api_client.dart';

/// Fetches the authenticated user's complete business restore snapshot.
///
/// The restore endpoint is intentionally separate from ordinary sync pulls:
/// reinstall recovery needs a consistent snapshot of the business rather
/// than a collection of independent "current state" requests.
class CloudRestoreApi {
  CloudRestoreApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchSnapshot({required String businessId}) async {
    try {
      final response = await _client.dio.post(
        '/functions/v1/fulus-restore',
        data: {'business_id': businessId},
      );
      return Map<String, dynamic>.from(
        (response.data as Map<String, dynamic>)['data'] as Map,
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
