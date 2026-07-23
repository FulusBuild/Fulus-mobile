import '../entities/income_record.dart';

/// Architecture Section 4's repository pattern, applied to
/// IncomeRecords. Same write shape as ExpenseRepository/SaleRepository.
abstract class IncomeRecordRepository {
  Future<IncomeRecord> recordIncome(IncomeRecordDraft draft);

  Stream<List<IncomeRecord>> watchIncomeForLocation(String locationId);

  Future<void> markSynced({required String localId, required String serverId});
}
