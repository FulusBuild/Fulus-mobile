/// Volume 8, Decision 26: "A supplier's balance works exactly like the
/// customer credit book (Volume 7), mirrored." See tables.dart's
/// `SupplierLedgerEntries` doc comment for the full "100% local-only,
/// no backend column at all" gap this reflects.
enum SupplierLedgerEntryType {
  /// Increases the balance. Volume 8: "accumulated whenever Stock In
  /// (Volume 6) records a cost price that wasn't paid on the spot."
  /// Written by `ProductRepository.recordStockIn`'s caller when a
  /// supplier and an unpaid cost are both present on that stock-in — see
  /// `SupplierCreditRepository.recordStockPurchaseOnCredit`'s own doc
  /// comment for exactly where that decision is made (not inside the
  /// stock-in write path itself, the same "mechanics here, decision at
  /// the call site" split every cross-domain trigger in this codebase
  /// follows).
  stockPurchaseOnCredit,

  /// Decreases the balance. Volume 8: "Recording a payment reduces the
  /// balance the same way a customer repayment does — same interaction,
  /// opposite direction."
  paymentMade;
}

class SupplierLedgerEntry {
  const SupplierLedgerEntry({
    required this.localId,
    required this.supplierLocalId,
    required this.entryType,
    required this.amount,
    this.paymentMethod,
    this.note,

    /// Optional link to the [StockMovement] (Stage 5) whose stock-in
    /// created this entry, when this is a
    /// [SupplierLedgerEntryType.stockPurchaseOnCredit] row. Mirrors
    /// `CustomerLedgerEntry.saleLocalId`'s own optional-link pattern.
    this.stockMovementLocalId,
    required this.createdAt,
  });

  final String localId;
  final String supplierLocalId;
  final SupplierLedgerEntryType entryType;

  /// Always the positive, raw amount — direction implied by [entryType],
  /// same convention `CustomerLedgerEntry.amount` uses.
  final double amount;

  final String? paymentMethod;
  final String? note;
  final String? stockMovementLocalId;
  final DateTime createdAt;
}
