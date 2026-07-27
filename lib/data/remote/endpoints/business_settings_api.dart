import 'package:dio/dio.dart';

import '../../../domain/entities/business_settings.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/settings.py's
/// GET /api/settings/business-profile, verified directly
/// (response_model=BusinessProfileOut) — a single JSON object, not a
/// list. Any authenticated user can read it (no role restriction on
/// this route) — matches GET /api/locations and
/// GET /api/auth/approval-hashes' same "reference data every device
/// needs" reasoning.
///
/// No corresponding write method here: PUT /api/settings/business-profile
/// exists on the backend (admin-only) but BusinessSettingsRepository has
/// no create/update method to call it from — desktop-managed, per that
/// interface's own doc comment, the same as Location.
class BusinessSettingsApi {
  BusinessSettingsApi(this._client);

  final ApiClient _client;

  Future<BusinessSettingsResponseDto> getBusinessProfile() async {
    try {
      final response = await _client.dio.get('/api/settings/business-profile');
      return BusinessSettingsResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
