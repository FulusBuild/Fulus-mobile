import 'package:drift/drift.dart';

import '../local/database/database.dart';

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
    required Map<String, double> refundedAmountBySale,
    required Map<String, double> refundedCostBySale,
    required Map<String, Map<String, ({int quantity, double amount})>> refundedByProductBySale,
  })  : _refundedAmountBySale = refundedAmountBySale,
        _refundedCostBySale = refundedCostBySale,
        _refundedByProductBySale = refundedByProductBySale;

  static final SaleReversalAdjustments empty = SaleReversalAdjustments._(
    voidedSaleIds: const {},
    refundedAmountBySale: const {},
    refundedCostBySale: const {},
    refundedByProductBySale: const {},
  );

  final Set<String> voidedSaleIds;
  final Map<String, double> _refundedAmountBySale;
  final Map<String, double> _refundedCostBySale;
  final Map<String, Map<String, ({int quantity, double amount})>> _refundedByProductBySale;

  bool isVoided(String saleLocalId) => voidedSaleIds.contains(saleLocalId);

  /// Total refunded (non-void, completed returns only) against this sale.
  double refundedAmountFor(String saleLocalId) => _refundedAmountBySale[saleLocalId] ?? 0.0;

  /// Total cost-of-goods-sold attributable to refunded (non-void)
  /// quantity against this sale — weighted-average cost per product,
  /// same fairness convention `ReturnRepositoryImpl._weightedAveragePrice`
  /// already uses for refund pricing, applied here to `costPriceAtSale`
  /// instead of `unitPrice`.
  double refundedCostFor(String saleLocalId) => _refundedCostBySale[saleLocalId] ?? 0.0;

  /// Per-product (quantity, amount) refunded against this sale — for
  /// netting Top Products at the line level.
  Map<String, ({int quantity, double amount})> refundedItemsFor(String saleLocalId) =>
      _refundedByProductBySale[saleLocalId] ?? const {};

  /// The net revenue this sale should contribute: 0 if voided
  /// (excluded entirely), otherwise the sale's total less whatever's
  /// been refunded against it — floored at 0 so a data inconsistency
  /// (a refund somehow exceeding the sale total) can't go negative.
  double netRevenue(SaleRow sale) {
    if (isVoided(sale.localId)) return 0.0;
    final net = sale.total - refundedAmountFor(sale.localId);
    return net < 0 ? 0.0 : net;
  }

  /// The net cost-of-goods-sold this sale should contribute — mirrors
  /// [netRevenue]'s own voided/refunded treatment, applied to
  /// [rawCost] (the sale's own `sum(costPriceAtSale * quantity)`,
  /// passed in rather than recomputed here since callers already have
  /// each sale's items loaded).
  double netCostOfGoodsSold(String saleLocalId, double rawCost) {
    if (isVoided(saleLocalId)) return 0.0;
    final net = rawCost - refundedCostFor(saleLocalId);
    return net < 0 ? 0.0 : net;
  }

  /// The net cash this sale should be treated as having brought in —
  /// for cash-flow, not revenue. `amountPaid` less whatever of that
  /// payment has actually been given back. A refund/void can only ever
  /// return cash that was actually collected — the excess (reversing
  /// an unpaid credit balance) is a credit-balance adjustment
  /// (`CustomerCreditRepository.recordRefundAdjustment` already
  /// handles that separately), never cash leaving twice.
  double netCashReceived(SaleRow sale) {
    final reversedValue = isVoided(sale.localId) ? sale.total : refundedAmountFor(sale.localId);
    final cashGivenBack = reversedValue < sale.amountPaid ? reversedValue : sale.amountPaid;
    final net = sale.amountPaid - cashGivenBack;
    return net < 0 ? 0.0 : net;
  }

  static Future<SaleReversalAdjustments> load(AppDatabase db, Set<String> saleIds) async {
    if (saleIds.isEmpty) return empty;

    final completedReturns = await (db.select(db.returnRequests)
          ..where((r) => r.originalSaleLocalId.isIn(saleIds) & r.status.equals('completed')))
        .get();
    if (completedReturns.isEmpty) return empty;

    final saleIdByReturnId = {for (final r in completedReturns) r.localId: r.originalSaleLocalId};
    final isVoidByReturnId = {for (final r in completedReturns) r.localId: r.isVoid};
    final voidedSaleIds = completedReturns.where((r) => r.isVoid).map((r) => r.originalSaleLocalId).toSet();

    final returnItems = await (db.select(db.returnItems)
          ..where((i) => i.returnLocalId.isIn(saleIdByReturnId.keys)))
        .get();
    if (returnItems.isEmpty) {
      return SaleReversalAdjustments._(
        voidedSaleIds: voidedSaleIds,
        refundedAmountBySale: const {},
        refundedCostBySale: const {},
        refundedByProductBySale: const {},
      );
    }

    // Weighted-average price/cost per (sale, product) — recomputed
    // from SaleItems directly rather than trusted off ReturnRequests.
    // refundAmount (one aggregate figure across every line in a
    // possibly multi-product return, not a per-product breakdown), so
    // refunded quantity can be priced and costed back out product by
    // product for Top Products / COGS netting.
    final saleItems = await (db.select(db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
    final linesBySaleProduct = <String, Map<String, ({int quantity, double amount, double cost})>>{};
    for (final item in saleItems) {
      final productId = item.productLocalId;
      if (productId == null) continue;
      final bySale = linesBySaleProduct.putIfAbsent(item.saleLocalId, () => {});
      final existing = bySale[productId];
      bySale[productId] = (
        quantity: (existing?.quantity ?? 0) + item.quantity,
        amount: (existing?.amount ?? 0) + item.quantity * item.unitPrice,
        cost: (existing?.cost ?? 0) + item.quantity * item.costPriceAtSale,
      );
    }

    final refundedAmountBySale = <String, double>{};
    final refundedCostBySale = <String, double>{};
    final refundedByProductBySale = <String, Map<String, ({int quantity, double amount})>>{};

    for (final item in returnItems) {
      final saleId = saleIdByReturnId[item.returnLocalId];
      if (saleId == null) continue;
      // A voided sale is excluded wholesale by the caller (via
      // voidedSaleIds) — its return items aren't netted line-by-line
      // on top of that, which would double-subtract.
      if (isVoidByReturnId[item.returnLocalId] ?? false) continue;

      final line = linesBySaleProduct[saleId]?[item.productLocalId];
      final unitPrice = (line == null || line.quantity == 0) ? 0.0 : line.amount / line.quantity;
      final unitCost = (line == null || line.quantity == 0) ? 0.0 : line.cost / line.quantity;
      final refundedAmount = unitPrice * item.quantity;
      final refundedCost = unitCost * item.quantity;

      refundedAmountBySale[saleId] = (refundedAmountBySale[saleId] ?? 0) + refundedAmount;
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
      refundedCostBySale: refundedCostBySale,
      refundedByProductBySale: refundedByProductBySale,
    );
  }
}
