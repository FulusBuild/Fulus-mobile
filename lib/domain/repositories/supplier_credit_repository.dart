import '../../core/money/money.dart';
import '../entities/supplier_ledger_entry.dart';

/// Volume 8, Decision 26's "mirrors the customer credit book" made
/// literal — same shape as `CustomerCreditRepository`, opposite
/// direction. See tables.dart's `SupplierLedgerEntries` doc comment for
/// why ledger writes require an explicit location and are synchronized as
/// canonical business financial operations.
abstract class SupplierCreditRepository {
  /// Called when Stock In (Stage 5) records a cost that wasn't paid on
  /// the spot, for a product with a supplier set. **Not called
  /// automatically by `ProductRepository.recordStockIn` itself** — that
  /// method has no concept of "was this paid for," only "how much
  /// stock arrived." The decision that a given stock-in was unpaid, and
  /// the resulting call here, belongs to whatever composes the Stock In
  /// screen (it already has to ask "paid now or on account" per Volume
  /// 6's own UI, the same UI-level fact this repository has no way to
  /// know on its own) — same "mechanics here, decision at the call
  /// site" split every cross-domain trigger in this codebase follows
  /// (e.g. `CustomerCreditRepository.recordCreditSale`, called by Sales
  /// rather than firing itself).
  Future<SupplierLedgerEntry> recordStockPurchaseOnCredit({
    required String supplierLocalId,
    required Money amount,
    String? stockMovementLocalId,
    required String locationLocalId,
  });

  /// Volume 8: "Recording a payment reduces the balance the same way a
  /// customer repayment does." Same clamp-at-zero safety
  /// `CustomerCreditRepository.recordRepayment` has, for the same
  /// Volume-7-originated failure scenario (a payment recorded larger
  /// than what's actually owed).
  Future<({SupplierLedgerEntry entry, Money newBalance, Money excessAmount})>
      recordPayment({
    required String supplierLocalId,
    required Money amount,
    String? paymentMethod,
    String? note,
    required String locationLocalId,
    String? cashDrawerShiftLocalId,
  });

  Stream<List<SupplierLedgerEntry>> watchLedger(String supplierLocalId);

  /// Every [SupplierLedgerEntryType.paymentMade] entry with `createdAt`
  /// inside [start, end] (inclusive of both ends' full calendar days).
  /// When [locationLocalId] is provided, only entries attributed to that
  /// location are returned. Null preserves the business-wide legacy query.
  Future<List<SupplierLedgerEntry>> getPaymentsForPeriod({
    required DateTime start,
    required DateTime end,
    String? locationLocalId,
  });

  Future<void> reconcileServerEntry({
    required String serverId,
    required String operationId,
    required String supplierServerId,
    required String locationServerId,
    String? stockMovementServerId,
    String? cashDrawerShiftServerId,
    required SupplierLedgerEntryType entryType,
    required Money amount,
    required Money balanceAfter,
    String? paymentMethod,
    String? note,
    required DateTime createdAt,
  });
}
