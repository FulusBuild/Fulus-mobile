import 'package:drift/drift.dart';

import '../../domain/entities/finance_stats.dart';
import '../../domain/repositories/finance_stats_repository.dart';
import '../local/database/database.dart';

class FinanceStatsRepositoryImpl implements FinanceStatsRepository {
  FinanceStatsRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

  @override
  Future<ProfitLossReport> getProfitLoss({
    required DateTime dateFrom,
    required DateTime dateTo,
    required String locationId,
  }) async {
    // NOTE: Sales has no `status` column — every row in this table already
    // represents a finished transaction (drafts live separately, in
    // DraftCarts); there is no pending/completed/voided state to filter on
    // here, on this table or on the backend Sale model it mirrors (which
    // has `payment_status`, a different concept, not a transaction-status
    // field). Filtering on `deletedAt.isNull()` instead, matching every
    // other repository's soft-delete convention in this codebase.
    final saleRows = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.locationId.equals(locationId) &
                s.deletedAt.isNull() &
                s.saleDate.isBiggerOrEqualValue(dateFrom) &
                s.saleDate.isSmallerOrEqualValue(dateTo),
          ))
        .get();

    final revenue =
        saleRows.fold<double>(0.0, (sum, sale) => sum + sale.total);

    var costOfGoodsSold = 0.0;
    var totalUnitsSold = 0;
    var unitsWithCostRecorded = 0;
    for (final sale in saleRows) {
      final items = await (_db.select(_db.saleItems)
            ..where((i) => i.saleLocalId.equals(sale.localId)))
          .get();
      for (final item in items) {
        costOfGoodsSold += item.costPriceAtSale * item.quantity;
        totalUnitsSold += item.quantity;
        if (item.costPriceAtSale > 0) {
          unitsWithCostRecorded += item.quantity;
        }
      }
    }

    final expenseRows = await (_db.select(_db.expenses)
          ..where(
            (e) =>
                e.locationId.equals(locationId) &
                e.deletedAt.isNull() &
                e.expenseDate.isBiggerOrEqualValue(dateFrom) &
                e.expenseDate.isSmallerOrEqualValue(dateTo),
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
    final saleRows = await (_db.select(_db.sales)
          ..where(
            (s) =>
                s.locationId.equals(locationId) &
                s.deletedAt.isNull() &
                s.saleDate.isBiggerOrEqualValue(dateFrom) &
                s.saleDate.isSmallerOrEqualValue(dateTo),
          ))
        .get();
    final salesInflow =
        saleRows.fold<double>(0.0, (sum, s) => sum + s.amountPaid);

    final incomeRows = await (_db.select(_db.incomeRecords)
          ..where(
            (i) =>
                i.locationId.equals(locationId) &
                i.deletedAt.isNull() &
                i.incomeDate.isBiggerOrEqualValue(dateFrom) &
                i.incomeDate.isSmallerOrEqualValue(dateTo),
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
                e.expenseDate.isSmallerOrEqualValue(dateTo),
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
                e.createdAt.isSmallerOrEqualValue(dateTo),
          ))
        .get();
    final supplierPaymentsOutflow =
        supplierPaymentRows.fold<double>(0.0, (sum, e) => sum + e.amount);

    final inflow = salesInflow + manualIncomeInflow;
    final outflow = expensesOutflow + supplierPaymentsOutflow;

    return CashFlowReport(
      dateFrom: dateFrom,
      dateTo: dateTo,
      salesInflow: _round2(salesInflow),
      manualIncomeInflow: _round2(manualIncomeInflow),
      inflow: _round2(inflow),
      expensesOutflow: _round2(expensesOutflow),
      supplierPaymentsOutflow: _round2(supplierPaymentsOutflow),
      outflow: _round2(outflow),
      netCashFlow: _round2(inflow - outflow),
    );
  }
}
