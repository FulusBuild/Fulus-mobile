import '../entities/income_record.dart';

/// Architecture Section 4's repository pattern, applied to
/// IncomeRecords. Same write shape as ExpenseRepository/SaleRepository.
abstract class IncomeRecordRepository {
  Future<IncomeRecord> recordIncome(IncomeRecordDraft draft);

  /// [locationId] required, not optional — CORRECTED (see
  /// income_record.dart's own doc comment for the full story of getting
  /// this backwards, twice, before actually reading Architecture
  /// Section 7a). Matches SaleRepository.watchSalesForToday's identical
  /// treatment exactly. Previously
  /// `watchIncomeRecords({String? locationId})`.
  Stream<List<IncomeRecord>> watchIncomeRecords(String locationId);

  /// Needed by IncomeSyncHandler to fetch the persisted record at sync
  /// time (matching CustomerRepository.getCustomerById/
  /// ExpenseRepository.getExpenseById exactly) — missing from this
  /// interface entirely before now, since no sync handler existed yet
  /// to need it.
  Future<IncomeRecord?> getIncomeRecordById(String localId);

  /// All income records for [locationId] with `incomeDate` inside
  /// [start, end] (inclusive of both ends' full calendar days) — the
  /// period-scoped sibling of [watchIncomeRecords], added for Volume
  /// 8's Money/Cash Flow feature. One-shot Future, matching
  /// `features/money/data/money_repository.dart`'s own interface shape.
  Future<List<IncomeRecord>> getIncomeRecordsForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  });

  Future<void> markSynced({required String localId, required String serverId});
}
