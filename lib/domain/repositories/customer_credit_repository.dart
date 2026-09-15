import '../entities/customer_ledger_entry.dart';

abstract class CustomerCreditRepository {
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  });

  Future<({CustomerLedgerEntry entry, double newBalance, double excessAmount})>
      recordRepayment({
    required String customerLocalId,
    required double amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  });

  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  });

  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId);

  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
  });

  /// Applies a server-authoritative ledger entry without creating an
  /// outbound sync task. Server customer/sale IDs are resolved to local IDs.
  Future<void> reconcileServerState({
    required String serverId,
    required String customerServerId,
    String? saleServerId,
    required CustomerLedgerEntryType entryType,
    required double amount,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
    required DateTime updatedAt,
  });

  Future<void> reconcileDeleted(String serverId);
}
