import 'package:dio/dio.dart';

import '../../../domain/entities/expense.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/finance.py's POST /api/finance/expenses,
/// verified directly. No 409/idempotency special-casing needed here —
/// same reasoning as SalesApi.createSale and CustomersApi.createCustomer:
/// finance_service.create_expense's own idempotent-replay logic
/// (migration 0013_expense_client_reference) always returns the correct
/// expense with a normal 201, whether newly created or already existing.
class ExpensesApi {
  ExpensesApi(this._client);

  final ApiClient _client;

  Future<Expense> createExpense(ExpenseCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/finance/expenses',
        data: dto.toJson(),
      );
      final responseDto = ExpenseResponseDto.fromJson(response.data as Map<String, dynamic>);
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  Expense _toDomain(ExpenseResponseDto dto) {
    final now = DateTime.now();
    return Expense(
      localId: dto.id,
      // Same reasoning as SalesApi/CustomersApi._toDomain: only ever
      // called with a response that came FROM the server, so localId
      // and serverId are deliberately the same value here.
      serverId: dto.id,
      // No locationId at all — the server has no such concept for
      // expenses (see Expense's own doc comment); a synced-down/
      // server-confirmed Expense simply has none.
      categoryId: dto.categoryId,
      description: dto.description,
      amount: dto.amount,
      expenseDate: dto.expenseDate,
      paymentMethod: dto.paymentMethod,
      // Not present in ExpenseResponseDto — same reasoning as
      // CustomersApi._toDomain's identical caveat: only ever correct for
      // a response that just came directly from a create call.
      createdAt: now,
      updatedAt: now,
    );
  }
}
