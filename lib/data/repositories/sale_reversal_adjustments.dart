import 'package:drift/drift.dart';

import '../../core/money/money.dart';

import '../local/database/database.dart';
import 'sale_mapper.dart';

/// Reversal data for a set of sales — how much of each sale's revenue,
/// cost of goods sold, and cash received has been undone by a
/// completed void or return.
///
/// **The bug this closes (Reports audit — void/refund section):**
/// voiding a sale (`ReturnRepositoryImpl.voidSale`) never touches the
/// original `Sales` row at all — no status column, no `deletedAt`. It
/// only ever writes a completed `ReturnRequests` row with
/// `isVoid: true`. Before this class existed, the *only* place in the
/// app that ever checked a sale's return/void status was
/// `ReportsRepositoryImpl._buildSaleRecords` — purely for the
/// drill-down list's displayed label. Every actual number (Sales
/// report revenue/count/top-products/payment-method/hour breakdowns,
/// Finance's revenue and COGS, Customer's top-spender totals,
/// `FinanceStatsRepositoryImpl`'s cash-flow and profit/loss) summed
/// `Sales.total`/`amountPaid` completely unconditionally, counting
/// voided and refunded sales as if they were still valid. A
/// `deletedAt.isNull()` filter already present in
/// `FinanceStatsRepositoryImpl` claimed to guard against exactly this
/// — verified directly that nothing anywhere ever sets `Sales.
/// deletedAt`, so that filter was dead code, not a real guard.
///
/// This class is the one place that reversal logic now lives, shared
/// by every caller that needs it, so Reports and Finance Stats can't
/// drift apart on what counts as "reversed" the way Cash Flow's own
/// `customerRepaymentsInflow` gap once did (see that field's own doc
/// comment in `finance_stats.dart`).
///
/// **Business rule — voided vs. refunded:**
/// A **voided** sale is excluded wholesale — treated as never having
/// happened, matching `SaleRecordStatus.voided`'s own "the cashier's
/// own mistake" framing (`ReturnRequests.isVoid`'s doc comment in
/// tables.dart). A genuine **return** (`isVoid: false`) instead nets
/// only its refunded amount/quantity out of the sale it targets,
/// leaving the rest of a partial refund intact as a real, valid sale.
///
/// **Known scoping limitation**, inherited from how this schema
/// already attributes everything to `Sale.saleDate`: a return
/// completed in a *later* period than its original sale still adjusts
/// the ORIGINAL sale's period, not the period the return itself
/// happened in. This matches the convention `SaleRecordStatus` already
/// established (a sale's status is a property of the sale record
/// itself, not a separate ledger event with its own period) rather
/// than inventing a "returns happened in this period" concept this
/// schema has no data model for. Flagged here, not silently chosen.
class SaleReversalAdjustments {
  SaleReversalAdjustments._({
    required this.voidedSaleIds,
    required Map<String, Money> refundedAmountBySale,
    required Map<String, Money> creditReversedBySale,
    required Map<String, Money> refundedCostBySale,
    required Map<String, Map<String, ({int quantity, Money amount})>> refundedByProductBySale,
  })  : _refundedAmountBySale = refundedAmountBySale,
        _creditReversedBySale = creditReversedBySale,
        _refundedCostBySale = refundedCostBySale,
        _refundedByProductBySale = refundedByProductBySale;

  static final SaleReversalAdjustments empty = SaleReversalAdjustments._(
    voidedSaleIds: const {},
    refundedAmountBySale: const {},
    creditReversedBySale: const {},
    refundedCostBySale: const {},
    refundedByProductBySale: const {},
  );

  final Set<String> voidedSaleIds;
  final Map<String, Money> _refundedAmountBySale;
  final Map<String, Money> _creditReversedBySale;
  final Map<String, Money> _refundedCostBySale;
  final Map<String, Map<String, ({int quantity, Money amount})>> _refundedByProductBySale;

  bool isVoided(String saleLocalId) => voidedSaleIds.contains(saleLocalId);

  /// Total refunded (non-void, completed returns only) against this sale.
  Money refundedAmountFor(String saleLocalId) => _refundedAmountBySale[saleLocalId] ?? 0;

  /// Total cost-of-goods-sold attributable to refunded (non-void)
  /// quantity against this sale — weighted-average cost per product
  /// from the sale-time cost snapshots.
  Money refundedCostFor(String saleLocalId) => _refundedCostBySale[saleLocalId] ?? 0;

  /// Per-product (quantity, amount) refunded against this sale — for
  /// netting Top Products at the line level.
  Map<String, ({int quantity, Money amount})> refundedItemsFor(String saleLocalId) =>
      _refundedByProductBySale[saleLocalId] ?? const {};

  /// The net revenue this sale should contribute: 0 if voided
  /// (excluded entirely), otherwise the sale's total less whatever's
  /// been refunded against it — floored at 0 so a data inconsistency
  /// (a refund somehow exceeding the sale total) can't go negative.
  Money netRevenue(SaleRow sale) {
    if (isVoided(sale.localId)) return 0;
    final net = sale.total - refundedAmountFor(sale.localId);
    return net < 0 ? 0 : net;
  }

  /// The net cost-of-goods-sold this sale should contribute — mirrors
  /// [netRevenue]'s own voided/refunded treatment, applied to
  /// [rawCost] (the sale's own `sum(costPriceAtSale * quantity)`,
  /// passed in rather than recomputed here since callers already have
  /// each sale's items loaded).
  Money netCostOfGoodsSold(String saleLocalId, Money rawCost) {
    if (isVoided(saleLocalId)) return 0;
    final net = rawCost - refundedCostFor(saleLocalId);
    return net < 0 ? 0 : net;
  }

  /// The net cash this sale should be treated as having brought in —
  /// for cash-flow, not revenue. The local customer ledger records the
  /// part that reverses outstanding credit; only the remaining amount
  /// is cash owed back. Cash is capped at what the sale actually collected.
  Money netCashReceived(SaleRow sale) {
    final reversedValue = isVoided(sale.localId) ? sale.total : refundedAmountFor(sale.localId);
    final creditReversed = _creditReversedBySale[sale.localId] ?? 0;
    final cashRefund = reversedValue > creditReversed
        ? reversedValue - creditReversed
        : 0;
    final cashGivenBack = cashRefund < sale.amountPaid ? cashRefund : sale.amountPaid;
    final net = sale.amountPaid - cashGivenBack;
    return net < 0 ? 0 : net;
  }

  static Future<SaleReversalAdjustments> load(AppDatabase db, Set<String> saleIds) async {
    if (saleIds.isEmpty) return empty;

    final completedReturns = await (db.select(db.returnRequests)
          ..where((r) => r.originalSaleLocalId.isIn(saleIds) & r.status.equals('completed')))
        .get();
    if (completedReturns.isEmpty) return empty;

    final refundedAmountBySale = <String, Money>{};
    for (final request in completedReturns.where((row) => !row.isVoid)) {
      refundedAmountBySale[request.originalSaleLocalId] =
          (refundedAmountBySale[request.originalSaleLocalId] ?? 0) +
              request.refundAmount;
    }
    final creditLedgerRows = await (db.select(db.customerLedgerEntries)
          ..where((entry) =>
              entry.saleLocalId.isIn(saleIds) &
              entry.entryType.equals('refundAdjustment')))
        .get();
    final creditReversedBySale = <String, Money>{};
    for (final entry in creditLedgerRows) {
      final saleId = entry.saleLocalId;
      if (saleId == null) continue;
      creditReversedBySale[saleId] =
          (creditReversedBySale[saleId] ?? 0) + entry.amount;
    }

    final saleIdByReturnId = {for (final r in completedReturns) r.localId: r.originalSaleLocalId};
    final isVoidByReturnId = {for (final r in completedReturns) r.localId: r.isVoid};
    final voidedSaleIds = completedReturns.where((r) => r.isVoid).map((r) => r.originalSaleLocalId).toSet();

    final returnItems = await (db.select(db.returnItems)
          ..where((i) => i.returnLocalId.isIn(saleIdByReturnId.keys)))
        .get();
    if (returnItems.isEmpty) {
      return SaleReversalAdjustments._(
        voidedSaleIds: voidedSaleIds,
        refundedAmountBySale: refundedAmountBySale,
        creditReversedBySale: creditReversedBySale,
        refundedCostBySale: const {},
        refundedByProductBySale: const {},
      );
    }

    // Weighted-average cost per (sale, product) comes from sale-time
    // cost snapshots. The server's aggregate refund is authoritative for
    // revenue and cash projections; the Sale helper allocates that net
    // value to products for Top Products.
    final saleItems = await (db.select(db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
    final saleRows = await (db.select(db.sales)..where((sale) => sale.localId.isIn(saleIds))).get();
    final saleItemsById = <String, List<SaleItemRow>>{};
    final linesBySaleProduct = <String, Map<String, ({int quantity, Money cost})>>{};
    for (final item in saleItems) {
      saleItemsById.putIfAbsent(item.saleLocalId, () => []).add(item);
      final productId = item.productLocalId;
      if (productId == null) continue;
      final bySale = linesBySaleProduct.putIfAbsent(item.saleLocalId, () => {});
      final existing = bySale[productId];
      bySale[productId] = (
        quantity: (existing?.quantity ?? 0) + item.quantity,
        cost: (existing?.cost ?? 0) + item.quantity * item.costPriceAtSale,
      );
    }

    final salesById = {
      for (final row in saleRows)
        row.localId: row.toDomain(saleItemsById[row.localId] ?? const []),
    };

    final refundedCostBySale = <String, Money>{};
    final refundedByProductBySale = <String, Map<String, ({int quantity, Money amount})>>{};

    for (final item in returnItems) {
      final saleId = saleIdByReturnId[item.returnLocalId];
      if (saleId == null) continue;
      // A voided sale is excluded wholesale by the caller (via
      // voidedSaleIds) — its return items aren't netted line-by-line
      // on top of that, which would Money-subtract.
      if (isVoidByReturnId[item.returnLocalId] ?? false) continue;

      final line = linesBySaleProduct[saleId]?[item.productLocalId];
      final unitCost = (line == null || line.quantity == 0) ? 0 : (line.cost / line.quantity).round();
      final refundedAmount = salesById[saleId]?.refundAmountFor({
            item.productLocalId: item.quantity,
          }) ??
          0;
      final refundedCost = unitCost * item.quantity;

      refundedCostBySale[saleId] = (refundedCostBySale[saleId] ?? 0) + refundedCost;
      final byProduct = refundedByProductBySale.putIfAbsent(saleId, () => {});
      final existing = byProduct[item.productLocalId];
      byProduct[item.productLocalId] = (
        quantity: (existing?.quantity ?? 0) + item.quantity,
        amount: (existing?.amount ?? 0) + refundedAmount,
      );
    }

    return SaleReversalAdjustments._(
      voidedSaleIds: voidedSaleIds,
      refundedAmountBySale: refundedAmountBySale,
      creditReversedBySale: creditReversedBySale,
      refundedCostBySale: refundedCostBySale,
      refundedByProductBySale: refundedByProductBySale,
    );
  }
}
