/// Mirrors `finance_service.get_profit_loss`'s return shape, extended
/// with Volume 8, Decision 27's honest-completeness caveat — verified
/// directly that the backend does NOT implement this itself
/// (`get_profit_loss` sums `cost_price_at_sale` with no missing-data
/// tracking at all; a line with no recorded cost just silently
/// contributes 0 to COGS). Decision 27 explicitly rejects exactly that
/// as the wrong behavior ("Option 1: show a profit figure regardless,
/// silently treating missing cost prices as zero... Rejected — a
/// silently wrong number is worse than an admittedly incomplete one").
/// [costDataCompleteness] is this domain's own addition to close that
/// gap, not something read from the backend.
class ProfitLossReport {
  const ProfitLossReport({
    required this.dateFrom,
    required this.dateTo,
    required this.revenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
    required this.costDataCompleteness,
  });

  final DateTime dateFrom;
  final DateTime dateTo;

  /// Backend: `sum(s.total for s in sales)`, cancelled sales already
  /// excluded by the underlying query.
  final double revenue;

  /// Backend: `sum(item.cost_price_at_sale * item.quantity for item in
  /// items)` — silently includes zero-cost lines; see this class's own
  /// doc comment for why [costDataCompleteness] exists alongside it
  /// rather than trying to "fix" this figure by excluding them (that
  /// would just be a different silent distortion — the honest fix is
  /// showing how complete the underlying data is, not picking a
  /// different way to guess around gaps in it).
  final double costOfGoodsSold;

  final double grossProfit;

  /// Backend: `sum(e.amount for e in expenses)` for the same range.
  final double expenses;

  final double netProfit;

  /// **This domain's own addition** (Decision 27) — the fraction (0.0
  /// to 1.0) of sold *units* in this range whose line had a non-zero
  /// `costPriceAtSale` recorded. `1.0` doesn't guarantee every cost was
  /// entered accurately, only that something was recorded; `costOfGoodsSold`
  /// above should be read as a floor, not a precise figure, whenever
  /// this is below 1.0 — exactly Decision 27's own framing: "a profit
  /// figure with a visible caveat is more useful than either a false
  /// precision or a refusal to show anything."
  final double costDataCompleteness;
}

/// Mirrors `finance_service.get_cash_flow`'s definition — inflow is
/// every completed sale's `amountPaid` plus manual income, outflow is
/// expenses, **not** filtered to physical cash the way
/// `CashDrawerShiftRepository.computeExpectedCash` deliberately is
/// (verified directly: the backend's own `get_cash_flow` sums
/// `amount_paid` across every payment method, not just cash — "Cash
/// Flow" and "Cash Drawer" are two different, correctly distinct
/// concepts in this codebase, not the same thing computed two places).
///
/// **One real improvement over the backend's own version, not just a
/// mirror of it** — the backend's own docstring names its own
/// limitation directly: inflow is attributed to `Sale.sale_date`
/// (creation time) rather than when payment actually happened, and
/// explicitly says fixing this would need "a Payment model (sale_id,
/// amount, paid_at)." This domain already has exactly that —
/// `SalePayment.recordedAt` and `CustomerLedgerEntry.createdAt` — so
/// [supplierPaymentsOut]/the repayment portion of [inflow] are
/// attributed to when money actually moved, not when the originating
/// sale was created. See `FinanceStatsRepositoryImpl.getCashFlow`'s own
/// doc comment for exactly how each figure is sourced.
class CashFlowReport {
  const CashFlowReport({
    required this.dateFrom,
    required this.dateTo,
    required this.salesInflow,
    required this.manualIncomeInflow,
    required this.customerRepaymentsInflow,
    required this.inflow,
    required this.expensesOutflow,
    required this.supplierPaymentsOutflow,
    required this.outflow,
    required this.netCashFlow,
  });

  final DateTime dateFrom;
  final DateTime dateTo;
  final double salesInflow;
  final double manualIncomeInflow;

  /// **Confirmed bug fix (Reports & Auditability upgrade):** this
  /// component didn't exist before — `inflow` only ever summed
  /// `salesInflow + manualIncomeInflow`, silently omitting every
  /// customer repayment in the period. A different feature (Money)
  /// caught this independently and built its own correct aggregation
  /// rather than call this method — see
  /// `features/money/data/real_money_repository.dart`'s own doc
  /// comment for that history. Sourced from
  /// `CustomerCreditRepository.getRepaymentsForPeriod`, the same method
  /// Money already uses, so the two can't drift apart on this figure
  /// again. One real scoping caveat, inherited from that method rather
  /// than introduced here: it's business-wide, not location-scoped —
  /// `CustomerLedgerEntries` has no `locationId` column, because
  /// customers themselves aren't location-scoped in this data model.
  /// For a single-location business this is a non-issue; for a
  /// multi-location one, this component reflects repayments across
  /// every location, not just [locationId].
  final double customerRepaymentsInflow;

  final double inflow;
  final double expensesOutflow;

  /// **Not in the backend's own `get_cash_flow` at all** — verified
  /// directly; the backend's outflow is expenses only. Supplier
  /// payments (Decision 26) are real money leaving the business and
  /// belong in outflow just as much as an expense does; included here
  /// as a genuine, cited addition rather than silently left out because
  /// the backend doesn't have it either.
  final double supplierPaymentsOutflow;

  final double outflow;
  final double netCashFlow;
}
