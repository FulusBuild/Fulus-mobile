import 'package:dio/dio.dart';

import '../../../domain/entities/product.dart';
import '../../../domain/entities/stock_movement.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/inventory.py's three stock-movement
/// routes directly, verified directly against both the router and
/// app/services/inventory_service.py: there is no single generic
/// create-a-stock-movement endpoint, and none of the three return the
/// movement record itself — every one returns ProductOut (ProductResponseDto
/// here, in domain/entities/product.dart), the product's own state AFTER
/// the write. No 409/idempotency special-casing needed in any of the
/// three methods below — same reasoning as CustomersApi/ExpensesApi/
/// IncomeApi: inventory_service.stock_in/stock_out/adjust_stock's own
/// idempotent-replay logic (migration
/// 0015_stock_movement_client_reference, verified directly) always
/// returns the correct (current) product state with a normal 200,
/// whether this call actually applied the change or a replay of an
/// already-applied one.
///
/// currentStock/isLowStock/stockValue on every response below are
/// parsed (ProductResponseDto is a faithful, lossless mirror of
/// ProductOut) but then genuinely dropped at the `.toDomain()` call each
/// method makes before returning — see ProductResponseDto.toDomain's own
/// doc comment for why: there is no ProductRepositoryImpl in this phase
/// (ProductRepository itself is read/pull-sync-only, with no write
/// methods in its own interface), so there is nowhere on-device to
/// reconcile a fresher current_stock TO. A real, honest, currently-
/// unaddressed gap for whoever builds that repository next — not
/// something this class works around by inventing its own write path
/// into ProductStockLevels, which would just be a second, competing way
/// to write that table's data outside the repository that's supposed to
/// own it.
class StockMovementsApi {
  StockMovementsApi(this._client);

  final ApiClient _client;

  Future<Product> stockIn({
    required String productId,
    required StockInCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/stock-in',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<Product> stockOut({
    required String productId,
    required StockOutCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/stock-out',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Future<Product> adjustStock({
    required String productId,
    required StockAdjustmentCreateDto dto,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products/$productId/adjust-stock',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>).toDomain();
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
