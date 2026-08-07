import 'package:dio/dio.dart';

import '../../../domain/entities/product.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/inventory.py's GET /api/inventory/products,
/// verified directly (response_model=PaginatedResponse[ProductOut]).
/// Returns the raw [ProductResponseDto] list rather than mapping to
/// [Product] here — a deliberate departure from every other *Api class
/// in this codebase, which return domain entities directly. Those all
/// map one response to one entity; this one response needs to feed TWO
/// separate local tables (Products' catalog fields, ProductStockLevels'
/// currentStock) from the same [ProductResponseDto], and only the
/// caller (ProductRepositoryImpl) knows how to split that — handing back
/// the raw DTO keeps that decision there instead of forcing a lossy
/// `.toDomain()` before the caller ever sees the stock data.
class ProductsApi {
  ProductsApi(this._client);

  final ApiClient _client;

  /// [pageSize] capped at 200 server-side (`Query(le=200)` on
  /// list_products, verified directly) — passing more just gets
  /// silently clamped by FastAPI's own validation, not rejected, but
  /// callers should still stay under it deliberately rather than rely
  /// on that.
  Future<ProductListResponseDto> listProducts({int page = 1, int pageSize = 200}) async {
    try {
      final response = await _client.dio.get(
        '/api/inventory/products',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      return ProductListResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// **Phase 0 completion pass.** POST /api/inventory/products, verified
  /// directly against routers/inventory.py + schemas/inventory.py's
  /// ProductCreate. Same response shape as every other product-touching
  /// endpoint (StockMovementsApi's own doc comment) — ProductOut, back
  /// as a ProductResponseDto.
  Future<ProductResponseDto> createProduct(ProductCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/products',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  /// PATCH /api/inventory/products/{id} — ProductUpdate, same
  /// exclude-unset partial-update contract [ProductUpdateDto]'s own doc
  /// comment describes.
  Future<ProductResponseDto> updateProduct({
    required String productId,
    required ProductUpdateDto dto,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/api/inventory/products/$productId',
        data: dto.toJson(),
      );
      return ProductResponseDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }
}
