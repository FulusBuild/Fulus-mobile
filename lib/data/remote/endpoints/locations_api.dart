import 'package:dio/dio.dart';

import '../../../domain/entities/location.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/locations.py's GET /api/locations,
/// verified directly (response_model=list[LocationOut]) — a bare JSON
/// array, not wrapped in an object and not paginated. Unlike
/// AuthApi.getApprovalHashes (wrapped in ApprovalHashesResponseDto's
/// `hashes` field) or ProductsApi.listProducts (wrapped in a paginated
/// envelope), this endpoint has no wrapper at all: Phase 2's location-
/// management UI is the only thing that would ever make this list long
/// enough to need pagination, and it doesn't exist yet — today this
/// always returns exactly one item.
class LocationsApi {
  LocationsApi(this._client);

  final ApiClient _client;

  Future<List<LocationResponseDto>> getLocations() async {
    try {
      final response = await _client.dio.get('/api/locations');
      return (response.data as List<dynamic>)
          .map((item) => LocationResponseDto.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
