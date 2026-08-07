import 'package:dio/dio.dart';

import '../../../domain/entities/category.dart';
import '../api_client.dart';

/// Mirrors `backend/app/routers/inventory.py`'s category endpoints
/// (nested under `/api/inventory/categories`, verified directly — there
/// is no separate `categories.py` router file; category and supplier
/// endpoints both live inside the inventory router alongside products).
///
/// **No idempotency protection on create** — unlike CustomersApi/
/// SalesApi, `CategoryCreate` has no `client_reference` field at all
/// (confirmed directly against `backend/app/schemas/inventory.py`). A
/// sync retry after a dropped response can create a genuine duplicate
/// category server-side; this class doesn't invent a client-side
/// workaround for a guarantee the backend doesn't actually provide.
/// Named here rather than silently matched to CustomersApi's safer
/// pattern.
class CategoriesApi {
  CategoriesApi(this._client);

  final ApiClient _client;

  Future<Category> createCategory(CategoryCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/inventory/categories',
        data: dto.toJson(),
      );
      final responseDto = CategoryResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Category _toDomain(CategoryResponseDto dto) {
    final now = DateTime.now();
    return Category(
      localId: dto.id,
      // Same reasoning as CustomersApi._toDomain — only ever called
      // with a response that came FROM the server, so localId and
      // serverId are deliberately the same value; reconciling a
      // locally-created Category's own pre-existing localId with this
      // serverId is CategoryRepositoryImpl.markSynced's job.
      serverId: dto.id,
      name: dto.name,
      description: dto.description,
      // Not present in CategoryResponseDto — same stand-in reasoning as
      // CustomersApi._toDomain: only correct for a fresh create
      // response, not a general-purpose mapping.
      createdAt: now,
      updatedAt: now,
    );
  }
}
