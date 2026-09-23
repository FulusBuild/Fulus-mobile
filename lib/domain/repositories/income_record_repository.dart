import '../entities/income_record.dart';

/// Architecture Section 4's repository pattern, applied to IncomeRecords.
abstract class IncomeRecordRepository {
  Future<IncomeRecord> recordIncome(IncomeRecordDraft draft);

  Stream<List<IncomeRecord>> watchIncomeRecords(String locationId);

  Future<IncomeRecord?> getIncomeRecordById(String localId);

  Future<List<IncomeRecord>> getIncomeRecordsForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  });

  Future<void> markSynced({required String localId, required String serverId});

  /// Parks a permanently rejected local income record without deleting it.
  Future<void> markAttentionNeeded(String localId);

  /// Applies server-authoritative income state without creating an outbound
  /// sync task. The server location ID is resolved to this device's local
  /// location row before persistence.
  Future<void> reconcileServerState({
    required String serverId,
    required String locationServerId,
    required String source,
    required double amount,
    required DateTime incomeDate,
    String? notes,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });

  /// Applies a server-authoritative deletion without creating an outbound
  /// sync task.
  Future<void> reconcileDeleted(String serverId);
}
