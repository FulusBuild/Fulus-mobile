import '../entities/customer_ledger_entry.dart';
import '../../core/money/money.dart';

abstract class CustomerCreditRepository {
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  });

  Future<({CustomerLedgerEntry entry, Money newBalance, Money excessAmount})>
      recordRepayment({
    required String customerLocalId,
    required Money amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  });

  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required Money amount,
    required String saleLocalId,
  });

  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId);

  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
    String? locationId,
  });

  /// Applies a server-authoritative ledger entry without creating an
  /// outbound sync task. Server customer/sale IDs are resolved to local IDs.
  Future<void> reconcileServerState({
    required String serverId,
    required String customerServerId,
    String? saleServerId,
    required CustomerLedgerEntryType entryType,
    required Money amount,
    String? operationId,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
    required DateTime updatedAt,
  });

  Future<void> reconcileDeleted(String serverId);
}
