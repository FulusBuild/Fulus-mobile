import 'package:dio/dio.dart';

import '../../../domain/entities/supplier.dart';
import '../api_client.dart';

/// Same endpoint family as CategoriesApi — see that class's own doc
/// comment for the router location and the identical, confirmed
/// no-idempotency-protection status (`SupplierCreate` has no
/// `client_reference` field either).
class SuppliersApi {
  SuppliersApi(this._client);

  final ApiClient _client;

  Future<Supplier> createSupplier(SupplierCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/suppliers',
        data: dto.toJson(),
      );
      final responseDto = SupplierResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Supplier _toDomain(SupplierResponseDto dto) {
    final now = DateTime.now();
    return Supplier(
      localId: dto.id,
      serverId: dto.id,
      name: dto.name,
      phone: dto.phone,
      email: dto.email,
      address: dto.address,
      createdAt: now,
      updatedAt: now,
    );
  }
}
