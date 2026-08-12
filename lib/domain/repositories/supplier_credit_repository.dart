import '../entities/supplier_ledger_entry.dart';

/// Volume 8, Decision 26's "mirrors the customer credit book" made
/// literal — same shape as `CustomerCreditRepository`, opposite
/// direction. See tables.dart's `SupplierLedgerEntries` doc comment for
/// why this is entirely local-only, more so than the customer version.
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
    required double amount,
    String? stockMovementLocalId,
  });

  /// Volume 8: "Recording a payment reduces the balance the same way a
  /// customer repayment does." Same clamp-at-zero safety
  /// `CustomerCreditRepository.recordRepayment` has, for the same
  /// Volume-7-originated failure scenario (a payment recorded larger
  /// than what's actually owed).
  Future<({SupplierLedgerEntry entry, double newBalance, double excessAmount})>
      recordPayment({
    required String supplierLocalId,
    required double amount,
    String? paymentMethod,
    String? note,
  });

  Stream<List<SupplierLedgerEntry>> watchLedger(String supplierLocalId);

  /// Every [SupplierLedgerEntryType.paymentMade] entry across every
  /// supplier, with `createdAt` inside [start, end] (inclusive of both
  /// ends' full calendar days) — Volume 8's Cash Flow feed needs "every
  /// supplier payment this period," which [watchLedger] alone can't
  /// answer without an N-supplier fan-out. Deliberately business-wide,
  /// no locationId parameter — same reasoning as
  /// CustomerCreditRepository.getRepaymentsForPeriod: SupplierLedgerEntries
  /// has no locationId column (tables.dart), and Suppliers aren't
  /// location-scoped either.
  Future<List<SupplierLedgerEntry>> getPaymentsForPeriod({
    required DateTime start,
    required DateTime end,
  });
}
