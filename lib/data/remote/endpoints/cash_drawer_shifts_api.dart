import 'package:dio/dio.dart';

import '../../../domain/entities/cash_drawer_shift.dart';
import '../api_client.dart';

/// `POST /api/pos/shifts` (open) and `PATCH /api/pos/shifts/{id}/close`
/// (close) — both verified directly against
/// `backend/app/routers/pos.py`. **No idempotency protection on
/// open** — `ShiftOpen` has no `client_reference` field, checked
/// directly; see tables.dart's `CashDrawerShifts` doc comment for why
/// this specific gap is lower-risk in practice than the others sharing
/// it.
class CashDrawerShiftsApi {
  CashDrawerShiftsApi(this._client);

  final ApiClient _client;

  Future<CashDrawerShift> openShift(ShiftOpenDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/pos/shifts',
        data: dto.toJson(),
      );
      return _toDomain(
        ShiftResponseDto.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<CashDrawerShift> closeShift({
    required String serverId,
    required ShiftCloseDto dto,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/api/pos/shifts/$serverId/close',
        data: dto.toJson(),
      );
      return _toDomain(
        ShiftResponseDto.fromJson(response.data as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  CashDrawerShift _toDomain(ShiftResponseDto dto) {
    return CashDrawerShift(
      localId: dto.id,
      serverId: dto.id,
      cashierUserId: dto.cashierId,
      locationId: dto.locationId,
      openedAt: dto.openedAt,
      closedAt: dto.closedAt,
      openingCash: dto.openingCash,
      closingCash: dto.closingCash,
      cashDifference: dto.cashDifference,
    );
  }
}
