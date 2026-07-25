import 'package:dio/dio.dart';

import '../../../domain/entities/income_record.dart';
import '../api_client.dart';

/// Mirrors backend/app/routers/finance.py's POST /api/finance/income,
/// verified directly. No 409/idempotency special-casing needed here —
/// same reasoning as SalesApi.createSale, CustomersApi.createCustomer,
/// and ExpensesApi.createExpense: finance_service.create_income's own
/// idempotent-replay logic (migration 0014_income_client_reference,
/// re-verified directly against the current backend during this
/// session) always returns the correct income record with a normal
/// 201, whether newly created or already existing.
class IncomeApi {
  IncomeApi(this._client);

  final ApiClient _client;

  Future<IncomeRecord> createIncome(IncomeCreateDto dto) async {
    try {
      final response = await _client.dio.post(
        '/api/finance/income',
        data: dto.toJson(),
      );
      final responseDto = IncomeResponseDto.fromJson(response.data as Map<String, dynamic>);
      return _toDomain(responseDto);
    } on DioException catch (e) {
      throw _client.mapError(e);
    }
  }

  IncomeRecord _toDomain(IncomeResponseDto dto) {
    final now = DateTime.now();
    return IncomeRecord(
      localId: dto.id,
      // Same reasoning as SalesApi/CustomersApi/ExpensesApi._toDomain:
      // only ever called with a response that came FROM the server, so
      // localId and serverId are deliberately the same value here.
      serverId: dto.id,
      // No locationId at all — the server has no such concept for
      // income records (see IncomeRecord's own doc comment); a synced-
      // down/server-confirmed IncomeRecord simply has none.
      source: dto.source,
      amount: dto.amount,
      incomeDate: dto.incomeDate,
      notes: dto.notes,
      // Not present in IncomeResponseDto — same caveat as
      // ExpensesApi/CustomersApi._toDomain: only ever correct for a
      // response that just came directly from a create call.
      createdAt: now,
      updatedAt: now,
    );
  }
}
