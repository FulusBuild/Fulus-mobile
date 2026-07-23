/// Mirrors the IncomeRecords table exactly — miscellaneous income
/// outside of sales (Architecture Section 7a: locationId required, same
/// as Expenses and Sales).
class IncomeRecord {
  const IncomeRecord({
    required this.localId,
    this.serverId,
    required this.locationId,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String locationId;
  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// The not-yet-persisted input to IncomeRecordRepository.recordIncome.
class IncomeRecordDraft {
  const IncomeRecordDraft({
    required this.locationId,
    required this.source,
    required this.amount,
    required this.incomeDate,
    this.notes,
  });

  final String locationId;
  final String source;
  final double amount;
  final DateTime incomeDate;
  final String? notes;

  IncomeRecord toIncomeRecordEntity({required String localId}) {
    final now = DateTime.now();
    return IncomeRecord(
      localId: localId,
      locationId: locationId,
      source: source,
      amount: amount,
      incomeDate: incomeDate,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }
}
