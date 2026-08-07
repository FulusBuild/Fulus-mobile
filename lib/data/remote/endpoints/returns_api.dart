import 'package:dio/dio.dart';
import 'package:ulid/ulid.dart';

import '../../../domain/entities/return_request.dart';
import '../api_client.dart';

/// Mirrors `backend/app/routers/pos.py`'s return endpoints — verified
/// directly: `POST /api/pos/returns`, prefix confirmed from the
/// router's own `APIRouter(prefix="/api/pos", ...)`.
///
/// **No idempotency protection on create** — same confirmed gap as
/// `CategoriesApi`/`SuppliersApi`: `ReturnCreate` has no
/// `client_reference` field at all. See `ReturnCreateDto`'s own doc
/// comment.
class ReturnsApi {
  ReturnsApi(this._client);

  final ApiClient _client;

  Future<ReturnRequest> createReturn(ReturnCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/pos/returns',
        data: dto.toJson(),
      );
      final responseDto = ReturnResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  ReturnRequest _toDomain(ReturnResponseDto dto) {
    final now = DateTime.now();
    return ReturnRequest(
      localId: dto.id,
      // Same reasoning as every other *Api._toDomain in this codebase —
      // only ever called with a response that came FROM the server, so
      // localId and serverId are deliberately the same value;
      // reconciling a locally-created ReturnRequest's own pre-existing
      // localId with this serverId is the repository's job.
      serverId: dto.id,
      originalSaleLocalId: dto.originalSaleId,
      status: switch (dto.status) {
        'pending' => ReturnStatus.pending,
        'approved' => ReturnStatus.approved,
        'rejected' => ReturnStatus.rejected,
        'completed' => ReturnStatus.completed,
        _ => throw ArgumentError.value(dto.status, 'status', 'unrecognized'),
      },
      returnReason: dto.returnReason,
      refundAmount: dto.refundAmount,
      refundMethod: dto.refundMethod,
      inventoryRestored: dto.inventoryRestored,
      // Item identity (localId) is regenerated here rather than reused
      // from the request — the local ReturnItems rows created by
      // ReturnRepositoryImpl.createReturn already exist with their own
      // real ids by the time this response arrives; this list exists to
      // satisfy ReturnRequest's constructor, not to be re-written
      // anywhere.
      items: dto.items
          .map(
            (i) => ReturnItem(
              localId: Ulid().toString(),
              returnLocalId: dto.id,
              productLocalId: i.productId,
              quantity: i.quantity,
            ),
          )
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
  }
}
