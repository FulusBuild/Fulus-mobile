import 'package:dio/dio.dart';

import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_movement.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/inventory.py's three stock-movement
/// routes directly, verified directly against both the router and
/// app/services/inventory_service.py: there is no single generic
/// create-a-stock-movement endpoint, and none of the three return the
/// movement record itself — every one returns ProductOut
/// (ProductResponseDto here, in domain/entities/product.dart), the
/// product's own state AFTER the write. No 409/idempotency special-
/// casing needed in any of the three methods below — same reasoning as
/// CustomersApi/ExpensesApi/IncomeApi: inventory_service.stock_in/
/// stock_out/adjust_stock's own idempotent-replay logic (migration
/// 0015_stock_movement_client_reference, verified directly) always
/// returns the correct (current) product state with a normal 200,
/// whether this call actually applied the change or a replay of an
/// already-applied one.
///
/// Returns the raw [ProductResponseDto], not the lossy `.toDomain()`-
/// mapped [Product] — CORRECTED: an earlier version of this class
/// returned `Product`, silently dropping currentStock/isLowStock/
/// stockValue at the call site because ProductRepositoryImpl didn't
/// exist yet to reconcile them anywhere. It exists now
/// (ProductRepository.reconcileStockLevel specifically, added for this
/// exact purpose), and StockMovementSyncHandler is the real caller that
/// needs the raw currentStock to pass to it — returning the lossy type
/// here would have thrown away the one piece of data that whole method
/// exists to use.
class StockMovementsApi {
  StockMovementsApi(this._client);

  final ApiClient _client;

  Future<ProductResponseDto> stockIn({
    required String productId,
    required StockInCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/stock-in',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<ProductResponseDto> stockOut({
    required String productId,
    required StockOutCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/stock-out',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<ProductResponseDto> adjustStock({
    required String productId,
    required StockAdjustmentCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/adjust-stock',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
