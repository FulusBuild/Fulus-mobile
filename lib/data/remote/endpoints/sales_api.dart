import 'package:dio/dio.dart';

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

  /// A note on the 409 idempotent-retry case Architecture Section 5
  /// describes: that section states a retried createSale (same
  /// client_reference) gets "rejected with a 409" that must be special-
  /// cased. Verified directly against the actual current backend
  /// (sale_service.create_sale) rather than trusted from the doc: that
  /// function's own idempotent-replay logic — both the check-before-
  /// insert path and the IntegrityError-caught race path — explicitly
  /// returns the EXISTING sale with a normal 201, never a 409. This
  /// method previously special-cased a 409 here on the strength of the
  /// architecture doc's claim alone, without having verified that claim
  /// against sale_service.py directly at the time — exactly the kind of
  /// gap this codebase's own discipline elsewhere is about catching.
  /// Since the backend already resolves a replay transparently, this
  /// method needs no special-casing at all: a 201 always carries the
  /// correct sale, whether newly created or already existing.
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
      throw _client.mapError(e);
    }
  }

  /// locationLocalId is a required parameter here, not an afterthought —
  /// an earlier draft of this method tried to build a Sale without it and
  /// discovered partway through that it's genuinely not derivable from
  /// this endpoint's own response alone (GET /api/sales returns sales
  /// with no location field the mobile client could resolve back to a
  /// local Locations row on its own).
  ///
  /// No current caller in this codebase — createSale above no longer
  /// needs this (see its own comment on why the 409-based re-fetch this
  /// method was originally built for doesn't reflect real backend
  /// behavior). Kept as a standalone, general-purpose lookup — a manual
  /// "check whether this sale actually went through" utility a future
  /// troubleshooting screen could reasonably want — rather than removed,
  /// since it's still correct and independently useful, just not
  /// currently wired to anything.
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
