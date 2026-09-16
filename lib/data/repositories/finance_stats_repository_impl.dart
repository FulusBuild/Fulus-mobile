
import '../../domain/entities/finance_stats.dart';
import '../../domain/repositories/customer_credit_repository.dart';
import '../../domain/repositories/finance_stats_repository.dart';
import '../local/database/database.dart';
import 'sale_reversal_adjustments.dart';

class FinanceStatsRepositoryImpl implements FinanceStatsRepository {
  FinanceStatsRepositoryImpl({
    required AppDatabase db,
    required CustomerCreditRepository customerCreditRepository,
  })  : _db = db,
        _customerCreditRepository = customerCreditRepository;

  final AppDatabase _db;
  final CustomerCreditRepository _customerCreditRepository;

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

  /// **Bug fix (date/period-filter audit):** every query in this class
  /// used `dateTo` exactly as received, with `isSmallerOrEqualValue`.
  /// Every caller in this codebase treats `dateFrom`/`dateTo` as
  /// calendar-day boundaries (see ReportsRepositoryImpl's own
  /// `_endOfDay`, applied everywhere else in that sibling repository) —
  /// but nothing here ever did the equivalent for `dateTo`. Passed a
  /// bare midnight (exactly what `ReportPeriod.end` for "Today" is —
  /// `today == tomorrow's period.start`, i.e. start=end=midnight),
  /// `saleDate.isSmallerOrEqualValue(dateTo)` excluded every sale made
  /// after 00:00:00 that day — reproducing precisely the "Revenue:
  /// ₦7,500 while Money in from sales: ₦0" symptom this audit set out
  /// to trace, for any sale not made at exactly midnight. Existing
  /// tests never caught this because every sale they insert already
  /// happens to sit at a bare-midnight `DateTime(y, m, d)` timestamp,
  /// which passes the broken comparison by coincidence.
  DateTime _endOfDay(DateTime date) => DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  @override
  Future<ProfitLossReport> getProfitLoss({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String locationId,
  }) async {
    final rangeEnd = _endOfDay(dateTo);
    // NOTE: Sales has no `status` column — every row in this table already
    // represents a finished transaction (drafts live separately, in
    // DraftCarts); there is no pending/completed/voided state to filter on
    // here, on this table or on the backend Sale model it mirrors (which
    // has `payment_status`, a different concept, not a transaction-status
    // field). Filtering on `deletedAt.isNull()` instead, matching every
    // other repository's soft-delete convention in this codebase.
    //
    // **Bug fix (void/refund audit):** `deletedAt.isNull()` above reads
    // as if it excludes a voided sale — verified directly that nothing
    // anywhere in this codebase ever sets `Sales.deletedAt` (voiding a
    // sale only ever writes a completed `ReturnRequests` row; see
    // `SaleReversalAdjustments`' own doc comment for the full trace),
    // so that filter was never actually doing anything. Revenue and
    // cost of goods sold below are now netted through
    // `SaleReversalAdjustments` instead, which is the real guard.
    final saleRows = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.locationId.equals(locationId) &
                s.deletedAt.isNull() &
                s.saleDate.isBiggerOrEqualValue(dateFrom) &
                s.saleDate.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();

    final saleIds = saleRows.map((s) => s.localId).toSet();
    final adjustments = await SaleReversalAdjustments.load(_db, saleIds);
    final revenue = saleRows.fold<double>(0.0, (sum, sale) => sum + adjustments.netRevenue(sale));

    var costOfGoodsSold = 0.0;
    var totalUnitsSold = 0;
    var unitsWithCostRecorded = 0;
    if (saleIds.isNotEmpty) {
      final items = await (_db.select(_db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
      final rawCostBySale = <String, double>{};
      for (final item in items) {
        if (adjustments.isVoided(item.saleLocalId)) continue;
        final productId = item.productLocalId;
        final refundedQty = productId == null ? 0 : (adjustments.refundedItemsFor(item.saleLocalId)[productId]?.quantity ?? 0);
        final netQty = item.quantity - refundedQty;
        if (netQty <= 0) continue;
        rawCostBySale[item.saleLocalId] = (rawCostBySale[item.saleLocalId] ?? 0) + item.costPriceAtSale * item.quantity;
        totalUnitsSold += netQty;
        if (item.costPriceAtSale > 0) {
          unitsWithCostRecorded += netQty;
        }
      }
      costOfGoodsSold = rawCostBySale.entries.fold<double>(0.0, (sum, e) => sum + adjustments.netCostOfGoodsSold(e.key, e.value));
    }

    final expenseRows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(locationId) &
                e.deletedAt.isNull() &
                e.expenseDate.isBiggerOrEqualValue(dateFrom) &
                e.expenseDate.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();
    final expenses =
        expenseRows.fold<double>(0.0, (sum, e) => sum + e.amount);

    final grossProfit = revenue - costOfGoodsSold;
    final netProfit = grossProfit - expenses;
    // A range with no sold units has nothing to be incomplete about —
    // treated as fully "complete" (1.0) rather than the misleading 0/0.
    final completeness =
        totalUnitsSold == 0 ? 1.0 : unitsWithCostRecorded / totalUnitsSold;

    return ProfitLossReport(
      dateFrom: dateFrom,
      dateTo: dateTo,
      revenue: _round2(revenue),
      costOfGoodsSold: _round2(costOfGoodsSold),
      grossProfit: _round2(grossProfit),
      expenses: _round2(expenses),
      netProfit: _round2(netProfit),
      costDataCompleteness: _round2(completeness),
    );
  }

  @override
  Future<CashFlowReport> getCashFlow({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String locationId,
  }) async {
    final rangeEnd = _endOfDay(dateTo);
    // Sales inflow: every completed sale's amountPaid in range — same
    // definition the backend's own get_cash_flow uses (all payment
    // methods, not cash-only; see CashFlowReport's own doc comment for
    // why that's correct here, unlike the Shift's cash-only figure).
    // Attributed to Sale.saleDate, same as the backend — see this
    // method's own doc comment on CashFlowReport for the one place this
    // domain's richer data (SalePayment.recordedAt) could improve on
    // that attribution for a *future* pass; not done here because doing
    // it only for the sales-inflow half while everything else in this
    // report still uses creation-date attribution would make the
    // figures internally inconsistent with each other, which is worse
    // than a single consistently-defined (if backend-matching)
    // attribution throughout.
    //
    // **Bug fix (void/refund audit):** `amountPaid` used to be summed
    // unconditionally, including sales later voided or fully/partially
    // refunded — none of which give any of that cash back in this
    // table. Netted through `SaleReversalAdjustments.netCashReceived`
    // instead, which only ever gives back cash that was actually
    // collected (see that method's own doc comment for why the rest of
    // a reversed *credit* balance is a separate adjustment, not cash).
    final saleRows = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.locationId.equals(locationId) &
                s.deletedAt.isNull() &
                s.saleDate.isBiggerOrEqualValue(dateFrom) &
                s.saleDate.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();
    final adjustments = await SaleReversalAdjustments.load(_db, saleRows.map((s) => s.localId).toSet());
    final salesInflow =
        saleRows.fold<double>(0.0, (sum, s) => sum + adjustments.netCashReceived(s));

    final incomeRows = await (_db.select(_db.incomeRecords)
          ..where(
            (i) =>
                i.locationId.equals(locationId) &
                i.deletedAt.isNull() &
                i.incomeDate.isBiggerOrEqualValue(dateFrom) &
                i.incomeDate.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();
    final manualIncomeInflow =
        incomeRows.fold<double>(0.0, (sum, i) => sum + i.amount);

    final expenseRows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(locationId) &
                e.deletedAt.isNull() &
                e.expenseDate.isBiggerOrEqualValue(dateFrom) &
                e.expenseDate.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();
    final expensesOutflow =
        expenseRows.fold<double>(0.0, (sum, e) => sum + e.amount);

    // Supplier payments — this domain's own addition to outflow (see
    // CashFlowReport.supplierPaymentsOutflow's doc comment for the
    // confirmed backend gap). Genuinely well-attributed by real
    // payment-event timestamps, unlike sales inflow above — this ledger
    // has no "creation vs. payment date" ambiguity to begin with, since
    // every row IS a payment event.
    final supplierPaymentRows = await (_db.select(_db.supplierLedgerEntries)
          ..where(
            (e) =>
                e.entryType.equals('paymentMade') &
                e.createdAt.isBiggerOrEqualValue(dateFrom) &
                e.createdAt.isSmallerOrEqualValue(rangeEnd),
          ))
        .get();
    final supplierPaymentsOutflow =
        supplierPaymentRows.fold<double>(0.0, (sum, e) => sum + e.amount);

    // The confirmed fix — see CashFlowReport.customerRepaymentsInflow's
    // own doc comment for the full history of this gap. Business-wide,
    // not location-filtered (getRepaymentsForPeriod has no locationId
    // parameter — see that method's own doc comment for why).
    // Deliberately still passed the RAW dateTo, not rangeEnd — this
    // method already computes its own end-of-day boundary internally
    // from the date components it's given (see
    // CustomerCreditRepositoryImpl.getRepaymentsForPeriod), so it was
    // never affected by the bug this method just fixed for itself.
    final repayments = await _customerCreditRepository.getRepaymentsForPeriod(
      start: dateFrom,
      end: dateTo,
    );
    final customerRepaymentsInflow =
        repayments.fold<double>(0.0, (sum, r) => sum + r.amount);

    final inflow = salesInflow + manualIncomeInflow + customerRepaymentsInflow;
    final outflow = expensesOutflow + supplierPaymentsOutflow;

    return CashFlowReport(
      dateFrom: dateFrom,
      dateTo: dateTo,
      salesInflow: _round2(salesInflow),
      manualIncomeInflow: _round2(manualIncomeInflow),
      customerRepaymentsInflow: _round2(customerRepaymentsInflow),
      inflow: _round2(inflow),
      expensesOutflow: _round2(expensesOutflow),
      supplierPaymentsOutflow: _round2(supplierPaymentsOutflow),
      outflow: _round2(outflow),
      netCashFlow: _round2(inflow - outflow),
    );
  }
}
