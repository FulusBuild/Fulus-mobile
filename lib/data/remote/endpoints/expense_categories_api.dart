import 'package:dio/dio.dart';

import '../../../domain/entities/expense_category.dart';
import '../api_client.dart';

/// `POST /api/finance/categories` — verified directly against
/// `backend/app/routers/finance.py` (path is `/categories`, not
/// `/expense-categories` as the Dart class name might suggest — checked
/// rather than assumed after getting a URL wrong once already this
/// pass) and its role gate (`require_role(MANAGER, ADMIN)`, matching
/// Volume 8's "Who Can Do What": everything in this volume is
/// owner-only). The role check happens server-side; this class doesn't
/// duplicate it.
///
/// **No idempotency protection on create** — same confirmed gap as
/// Categories/Suppliers/Returns.
class ExpenseCategoriesApi {
  ExpenseCategoriesApi(this._client);

  final ApiClient _client;

  Future<ExpenseCategory> createExpenseCategory(
    ExpenseCategoryCreateDto dto,
  ) async {
    try {
      final response = await _client.dio.post(
        '/api/finance/categories',
        data: dto.toJson(),
      );
      final responseDto = ExpenseCategoryResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  ExpenseCategory _toDomain(ExpenseCategoryResponseDto dto) {
    final now = DateTime.now();
    return ExpenseCategory(
      localId: dto.id,
      serverId: dto.id,
      name: dto.name,
      createdAt: now,
      updatedAt: now,
    );
  }
}
