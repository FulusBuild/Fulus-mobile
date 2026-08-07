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
/// STALE COMMENT CORRECTED (Architecture Redesign, Stage 4): this used to
/// say there's no write method here because "BusinessSettingsRepository
/// has no create/update method to call it from" — true when written,
/// false since Stage 4 added createBusiness/updateSettings to close a
/// real offline-onboarding gap. Still no write method here, though, and
/// deliberately so now rather than by omission: those two methods are
/// local-only (no push to a remote Host at all yet) — there's no
/// PUT-equivalent call in this class to push to even if they wanted to.
/// Pushing local settings changes to a Host (mirroring the best-effort
/// pattern ApprovalPinRepositoryImpl.setOwnApprovalPin uses) is a real,
/// still-open Sync-layer capability, not something this self-audit pass
/// is claiming to have finished.
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
