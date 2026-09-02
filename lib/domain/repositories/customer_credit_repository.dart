import '../entities/customer_ledger_entry.dart';

/// The Credit Book — Volume 7: "a running balance... and a full ledger
/// underneath." Kept as its own repository rather than folded into
/// CustomerRepository since its three write methods each have a
/// genuinely different sync story (see CustomerLedgerEntryType's own
/// doc comments) that CustomerRepository's simple create/update/delete
/// shape doesn't need to carry.
abstract class CustomerCreditRepository {
  /// Called by `SaleRepositoryImpl._recordCreditSaleIfNeeded` whenever a
  /// sale completes with `balanceDue > 0` for a selected customer (or,
  /// with itemized `payments`, whenever a `'credit'`-method leg is
  /// present) — verified directly against that call site, not assumed.
  /// Also updates `Customers.outstandingBalance` — the two always
  /// change together, in one transaction, never independently.
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

  /// Called by ReturnRepositoryImpl's refund flow — verified directly
  /// against that call site, not assumed.
  Future<CustomerLedgerEntry> recordRefundAdjustment({
    required String customerLocalId,
    required double amount,
    required String saleLocalId,
  });

  /// Reverse-chronological — same convention every other history/ledger
  /// view in this codebase uses.
  Stream<List<CustomerLedgerEntry>> watchLedger(String customerLocalId);

  /// Every [CustomerLedgerEntryType.repayment] entry across every
  /// customer, with `createdAt` inside [start, end] (inclusive of both
  /// ends' full calendar days) — Volume 8's Cash Flow feed needs "every
  /// repayment this period," which [watchLedger] alone can't answer
  /// without an N-customer fan-out (it's scoped to one customer at a
  /// time). Deliberately business-wide, no locationId parameter —
  /// matches this repository's own established status (this class's
  /// own doc comment: "business-wide, need no locationId, already fully
  /// implemented"), since CustomerLedgerEntries has no locationId column
  /// to filter by (tables.dart) and Customers themselves aren't
  /// location-scoped either.
  Future<List<CustomerLedgerEntry>> getRepaymentsForPeriod({
    required DateTime start,
    required DateTime end,
  });
}
