import '../entities/finance_stats.dart';

abstract class FinanceStatsRepository {
  Future<ProfitLossReport> getProfitLoss({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String locationId,
  });

  Future<CashFlowReport> getCashFlow({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String locationId,
  });
}
