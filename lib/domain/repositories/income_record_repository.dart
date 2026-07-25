import '../entities/income_record.dart';

/// Architecture Section 4's repository pattern, applied to
/// IncomeRecords. Same write shape as ExpenseRepository/SaleRepository.
abstract class IncomeRecordRepository {
  Future<IncomeRecord> recordIncome(IncomeRecordDraft draft);

  /// [locationId] is an optional filter, not a required scope — same
  /// correction as ExpenseRepository.watchExpenses: IncomeRecord has no
  /// server-side location concept at all (see IncomeRecord's own doc
  /// comment), so most income records may have no location tag
  /// whatsoever. Omit it to watch every income record. Previously
  /// `watchIncomeForLocation(String locationId)` — a required parameter
  /// that assumed the same (wrong, for this entity) location-required
  /// model Expense's interface originally had before its own fix; a
  /// direct copy of that same mistake, made independently for Income
  /// rather than actually inherited from it.
  Stream<List<IncomeRecord>> watchIncomeRecords({String? locationId});

  /// Needed by IncomeSyncHandler to fetch the persisted record at sync
  /// time (matching CustomerRepository.getCustomerById/
  /// ExpenseRepository.getExpenseById exactly) — missing from this
  /// interface entirely before now, since no sync handler existed yet
  /// to need it.
  Future<IncomeRecord?> getIncomeRecordById(String localId);

  Future<void> markSynced({required String localId, required String serverId});
}
