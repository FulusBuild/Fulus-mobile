/// Volume 8, Decision 26: "A supplier's balance works exactly like the
import 'package:fulus_mobile/core/money/money.dart';

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
  paymentMade,
}

class SupplierLedgerEntry {
  const SupplierLedgerEntry({
    required this.localId,
    required this.supplierLocalId,
    required this.entryType,
    required this.amount,
    this.locationLocalId,
    this.paymentMethod,
    this.note,

    /// Optional link to the [StockMovement] (Stage 5) whose stock-in
    /// created this entry, when this is a
    /// [SupplierLedgerEntryType.stockPurchaseOnCredit] row. Mirrors
    /// `CustomerLedgerEntry.saleLocalId`'s own optional-link pattern.
    this.stockMovementLocalId,
    this.cashDrawerShiftLocalId,
    required this.createdAt,
  });

  final String localId;
  final String supplierLocalId;
  final SupplierLedgerEntryType entryType;

  /// Location where the payable was incurred or payment made. Nullable for
  /// historical entries whose location cannot be reconstructed safely.
  final String? locationLocalId;

  /// Always the positive, raw amount — direction implied by [entryType],
  /// same convention `CustomerLedgerEntry.amount` uses.
  final Money amount;

  final String? paymentMethod;
  final String? note;
  final String? stockMovementLocalId;

  /// The drawer session that funded a cash payment, when the payment was
  /// recorded while a drawer was open. Null means it was outside a session.
  final String? cashDrawerShiftLocalId;
  final DateTime createdAt;
}
