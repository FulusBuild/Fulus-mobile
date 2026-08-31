import '../entities/sale.dart';
import '../entities/sale_draft.dart';
import '../entities/sale_payment.dart';

/// Architecture Section 4's repository pattern, applied to Sales — the
/// one entity with a complete stack underneath it (table, domain
/// entity, DTOs, SalesApi endpoint) as of this checkpoint. Defined here
/// as an abstract Dart class with zero Flutter/Drift imports, per
/// Section 4's structural rule: `data/remote/` is never imported from
/// `features/`, only this interface is — enforced by which layer is
/// even ALLOWED to import what, not just by convention.
abstract class SaleRepository {
  /// Writes the sale locally, synchronously, inside a single
  /// transaction, and returns once that local write completes — per
  /// Section 4's single most important structural rule, this method
  /// never awaits a network call. The sale is enqueued for sync
  /// (Section 8) as part of the same call, but that enqueue only hands
  /// off to the queue; it does not wait for the item to actually sync.
  Future<Sale> createSale(SaleDraft draft);

  /// Reactive by design (Section 4: "the default for anything rendered
  /// on screen is reactive") — Home's hero total (Section 2) depends on
  /// this updating the moment a sale is created OR a background sync
  /// writes a reconciled row, with no manual refresh call anywhere.
  Stream<List<Sale>> watchSalesForToday(String locationId);

  /// The one-shot, non-reactive exception Section 4 explicitly carves
  /// out — for cases like loading a specific sale to build a refund
  /// draft, where a single point-in-time read is genuinely what's
  /// needed, not a live subscription.
  Future<Sale?> getSaleByLocalId(String localId);

  /// All sales for [locationId] with `saleDate` inside [start, end]
  /// (inclusive of both ends' full calendar days) — the period-scoped
  /// sibling of [watchSalesForToday], added for Volume 8's Money/Cash
  /// Flow feature, which needs an arbitrary period rather than always
  /// "today." One-shot Future, not a Stream, matching
  /// `features/money/data/money_repository.dart`'s own interface shape
  /// (Future-based throughout) rather than introducing a reactive query
  /// that feature doesn't ask for.
  Future<List<Sale>> getSalesForPeriod({
    required String locationId,
    required DateTime start,
    required DateTime end,
  });

  /// Reconciles a locally-created sale with the server's own identity
  /// once the (not-yet-built) sync engine successfully pushes it —
  /// named here, not left implicit, because sales_api.dart's own
  /// comment on SalesApi._toDomain already points here as the correct
  /// owner of this reconciliation: "the repository layer... is what
  /// reconciles a locally-created Sale's own pre-existing localId with
  /// the serverId this response carries." No caller of this exists yet
  /// in this checkpoint — the sync engine that will call it is
  /// Architecture Section 8's still-unbuilt processing loop.
  Future<void> markSynced({
    required String localId,
    required String serverId,
    required String invoiceNumber,
  });

  /// The individual payment legs behind a split-payment sale — see
  /// `SalePayment`'s own doc comment ("no backend equivalent, rides
  /// with parent, aggregates into Sale.paymentMethod/amountPaid").
  /// Bug fix: added so the transaction detail screen can show what a
  /// "Split" sale was actually paid with, instead of just the word
  /// "Split" — previously nothing read the `SalePayments` rows back out
  /// once written. Empty for a single-method sale (no rows were ever
  /// written for those); the caller already has `Sale.paymentMethod`/
  /// `amountPaid` for that ordinary case.
  Future<List<SalePayment>> getPaymentsForSale(String saleLocalId);
}
