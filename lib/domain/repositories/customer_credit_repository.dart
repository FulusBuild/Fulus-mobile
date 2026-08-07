import '../entities/customer_ledger_entry.dart';

/// The Credit Book — Volume 7: "a running balance... and a full ledger
/// underneath." Kept as its own repository rather than folded into
/// CustomerRepository since its three write methods each have a
/// genuinely different sync story (see CustomerLedgerEntryType's own
/// doc comments) that CustomerRepository's simple create/update/delete
/// shape doesn't need to carry.
abstract class CustomerCreditRepository {
  /// **Not called by anything in this pass.** The seam Sales (not yet
  /// reworked onto this real foundation) is expected to call when a
  /// sale completes with `balanceDue > 0` for a selected customer — same
  /// forward-built-ahead-of-its-caller status
  /// `ProductRepository.recordSaleStockDeduction`-equivalent methods
  /// have elsewhere in this codebase. Also updates
  /// `Customers.outstandingBalance` — the two always change together,
  /// in one transaction, never independently.
  Future<CustomerLedgerEntry> recordCreditSale({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  });

  /// Volume 7's "amount, method, done" action. [saleLocalId] is optional
  /// — see [CustomerLedgerEntryType.repayment]'s own doc comment for
  /// what setting it does and doesn't currently enable on the sync side;
  /// this method's own local behavior (balance update + ledger entry) is
  /// identical either way.
  ///
  /// Returns the created entry alongside `computeRepaymentEffect`'s own
  /// `(newBalance, excessAmount)` — `excessAmount` is non-zero exactly
  /// when Volume 7's named failure scenario happened (a repayment larger
  /// than what was owed); the caller is expected to surface that rather
  /// than let it disappear silently.
  Future<({CustomerLedgerEntry entry, double newBalance, double excessAmount})>
      recordRepayment({
    required String customerLocalId,
    required double amount,
    String? paymentMethod,
    String? note,
    String? saleLocalId,
  });

  /// **Not called by anything in this pass** — same forward-seam status
  /// as [recordCreditSale], for the Returns workflow once it exists.
  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  });

  /// Reverse-chronological — same convention every other history/ledger
  /// view in this codebase uses.
  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId);
}
