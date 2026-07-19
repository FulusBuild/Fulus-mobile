import 'package:dio/dio.dart';

import '../../../core/errors/failure.dart';
import '../../../domain/entities/sale.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/sales.py directly — file naming and
/// method-per-endpoint structure per Architecture Section 5's stated
/// convention, so a change to that backend file has an obvious mobile
/// counterpart to check. Verified directly against the router's actual
/// current shape: create_sale requires SALE_WRITE_ROLES (cashier/
/// manager/admin — all reachable from mobile), update_sale and
/// cancel_sale require SALE_OVERSIGHT_ROLES (manager/admin only) — a
/// cashier-role mobile session calling update or cancel will get a real
/// 403 from the server, mapped to AuthFailure.forbidden by api_client.dart,
/// which is the expected, correct outcome per that file's own reasoning,
/// not a bug in this class.
class SalesApi {
  SalesApi(this._client);

  final ApiClient _client;

  /// The one method in this whole codebase where a 409 is deliberately
  /// intercepted BEFORE api_client.dart's general mapError ever sees it
  /// — per Architecture Section 5's explicit warning about this exact
  /// case: "if the sync engine retries a createSale task because a
  /// previous attempt's response was lost... the backend's unique
  /// constraint on client_reference will reject the retry with a 409.
  /// This must be special-cased to not surface as an error." Getting
  /// this wrong (letting it fall through to the generic BusinessRuleFailure
  /// mapError produces for an unhandled 409) would make the sync engine
  /// treat an already-successful sale as failed — the exact "phantom
  /// failure" risk named directly in that section.
  Future<Sale> createSale({
    required SaleCreateDto dto,
    required String locationLocalId,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/sales',
        data: dto.toJson(),
      );
      final responseDto = SaleResponseDto.fromJson(response.data as Map<String, dynamic>);
      return _toDomain(responseDto, locationLocalId: locationLocalId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // This IS the success case, per the reasoning above — the sale
        // already exists server-side under this exact client_reference.
        // Fetch it by that reference to get its real server-assigned
        // fields (invoice_number, server id) rather than fabricating a
        // success response locally, which would risk the local mirror
        // disagreeing with what the server actually recorded.
        final existing = await getSaleByClientReference(
          dto.clientReference!,
          locationLocalId: locationLocalId,
        );
        if (existing != null) return existing;

        // If the 409 fired but the immediate re-fetch genuinely can't
        // find a matching sale (a narrow race: the server's unique
        // constraint fired on a row not yet visible to a subsequent read
        // under whatever isolation level is in effect), this is treated
        // as a real, if unusual, failure rather than silently assumed
        // successful — silently assuming success with no confirming data
        // would be worse than surfacing it as needing attention.
        throw BusinessRuleFailure(
          'Could not confirm this sale — it may already be recorded. Please check Sales history before retrying.',
        );
      }
      throw _client.mapError(e);
    }
  }

  /// locationLocalId is a required parameter here, not an afterthought —
  /// an earlier draft of this method tried to build a Sale without it and
  /// discovered partway through that it's genuinely not derivable from
  /// this endpoint's own response alone (GET /api/sales returns sales
  /// with no location field the mobile client could resolve back to a
  /// local Locations row on its own). Rather than leave that gap papered
  /// over with a thrown UnimplementedError sitting behind code that looks
  /// finished, the caller — which always has this context already, since
  /// createSale's 409 branch above is the only real caller and it has the
  /// original draft's locationLocalId in scope — is required to supply it.
  Future<Sale?> getSaleByClientReference(
    String clientReference, {
    required String locationLocalId,
  }) async {
    try {
      final response = await _client.dio.get(
        '/api/sales',
        queryParameters: {'client_reference': clientReference},
      );
      final items = (response.data['items'] as List?) ?? [];
      if (items.isEmpty) return null;
      final dto = SaleResponseDto.fromJson(items.first as Map<String, dynamic>);
      return _toDomain(dto, locationLocalId: locationLocalId);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<Sale> updateSale({
    required String serverId,
    required double amountPaid,
    required String locationLocalId,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/api/sales/$serverId',
        data: {'amount_paid': amountPaid},
      );
      final dto = SaleResponseDto.fromJson(response.data as Map<String, dynamic>);
      return _toDomain(dto, locationLocalId: locationLocalId);
    } on DioException catch (e) {
      // No special-casing needed here — update_sale has no idempotency
      // key mechanism (verified directly: it PATCHes an existing,
      // already-server-known resource by its real server ID, not a
      // create-with-client-reference call), so a 409 here, if the
      // backend ever produced one for this endpoint, would be a genuine
      // conflict, correctly handled by the general mapError path.
      throw _client.mapError(e);
    }
  }

  Future<void> cancelSale(String serverId) async {
    try {
      await _client.dio.delete('/api/sales/$serverId');
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Sale _toDomain(SaleResponseDto dto, {required String locationLocalId}) {
    return Sale(
      localId: dto.id,
      // Deliberately the SAME value for localId and serverId here — this
      // method is only ever called with a response that came FROM the
      // server, so there is no separate local-only identity to preserve;
      // the repository layer (data/repositories/sale_repository.dart,
      // not yet implemented in this phase) is what reconciles a
      // locally-created Sale's own pre-existing localId with the
      // serverId this response carries, rather than this mapping
      // function inventing that reconciliation itself.
      serverId: dto.id,
      clientReference: dto.id,
      invoiceNumber: dto.invoiceNumber,
      customerId: dto.customerId,
      locationId: locationLocalId,
      saleDate: dto.saleDate,
      subtotal: dto.subtotal,
      discount: dto.discount,
      tax: dto.tax,
      total: dto.total,
      amountPaid: dto.amountPaid,
      paymentMethod: dto.paymentMethod,
      notes: dto.notes,
      items: dto.items
          .map((i) => SaleItem(
                localId: i.id,
                productLocalId: i.productId,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                costPriceAtSale: i.costPriceAtSale,
              ))
          .toList(),
      createdAt: dto.saleDate,
      updatedAt: dto.saleDate,
    );
  }
}
