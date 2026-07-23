import 'package:dio/dio.dart';

import '../../domain/entities/customer.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/customers.py directly, per Architecture
/// Section 5's file-per-router convention. create_customer requires no
/// special role beyond authentication (verified directly) — any mobile
/// session can add a walk-in customer at checkout.
class CustomersApi {
  CustomersApi(this._client);

  final ApiClient _client;

  /// No 409/idempotency special-casing needed here — verified directly
  /// against customer_service.create_customer (migration
  /// 0012_customer_client_reference): a retried create with the same
  /// client_reference always returns the existing customer with a
  /// normal 201, exactly mirroring the fix already applied to
  /// SalesApi.createSale for the identical reason (see that method's
  /// own comment on why the 409-based version was wrong).
  Future<Customer> createCustomer(CustomerCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/customers',
        data: dto.toJson(),
      );
      final responseDto = CustomerResponseDto.fromJson(response.data as Map<String, dynamic>);
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Customer _toDomain(CustomerResponseDto dto) {
    final now = DateTime.now();
    return Customer(
      localId: dto.id,
      // Same reasoning as SalesApi._toDomain: this is only ever called
      // with a response that came FROM the server, so localId and
      // serverId are deliberately the same value here — reconciling a
      // locally-created Customer's own pre-existing localId with this
      // serverId is CustomerRepositoryImpl.markSynced's job, not this
      // mapping function's.
      serverId: dto.id,
      name: dto.name,
      phone: dto.phone,
      email: dto.email,
      address: dto.address,
      notes: dto.notes,
      outstandingBalance: dto.outstandingBalance,
      // Not present in CustomerResponseDto at all (the backend doesn't
      // return timestamps for this endpoint) — using "now" as a
      // reasonable stand-in is only ever correct here for a customer
      // whose response just came directly from a create call, not a
      // general-purpose server->domain mapping (there's no
      // getCustomerByClientReference/list-based caller of this method
      // yet, unlike SalesApi's _toDomain, which is genuinely shared
      // across create/update/list responses that all really do carry a
      // sale_date).
      createdAt: now,
      updatedAt: now,
    );
  }
}
