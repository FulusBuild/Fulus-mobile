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
/// enough to need pagination — that UI exists now (see
/// `features/more/settings/presentation/screens/manage_locations_screen.dart`),
/// but a single mobile-managed business still only produces a handful
/// of locations at most, nowhere near needing pagination in practice.
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

  /// POST /api/locations — inferred by REST convention from the GET
  /// above (same path, same endpoint family shape as
  /// `POST /api/inventory/suppliers` sitting alongside
  /// `GET /api/inventory/suppliers`), **not verified against backend
  /// source**: backend/app/routers/locations.py wasn't available to
  /// check against in the pass that added this method, unlike the GET
  /// method above (which was verified directly). Flagged here rather
  /// than asserted, matching this codebase's own standard for an
  /// unverified endpoint. Response shape assumed identical to GET's
  /// per-item shape (`LocationOut` — just `id`/`name`), since a create
  /// endpoint returning anything narrower than its own list endpoint's
  /// item shape would be an unusual API design.
  Future<Location> createLocation(LocationCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/locations',
        data: dto.toJson(),
      );
      final responseDto = LocationResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Location _toDomain(LocationResponseDto dto) {
    final now = DateTime.now();
    return Location(
      localId: dto.id,
      serverId: dto.id,
      name: dto.name,
      createdAt: now,
      updatedAt: now,
    );
  }
}
