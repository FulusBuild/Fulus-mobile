import 'package:drift/drift.dart';

import 'employee_mapper.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/report.dart';
import '../../domain/repositories/reports_repository.dart';
import '../../domain/usecases/reports_engine.dart';
import '../local/database/database.dart';
import 'sale_reversal_adjustments.dart';

/// Same integration posture as receipt_repository_impl.dart: this is
/// the one place Stage 12's Reports half touches Sales/SaleItems/
/// Products/Customers/Expenses/IncomeRecords columns directly. Column
/// names verified against the same foundation-checkpoint tables.dart;
/// adjust queries here, not report.dart or reports_engine.dart, if the
/// merged Stage 5-8 schema differs.
class ReportsRepositoryImpl implements ReportsRepository {
  ReportsRepositoryImpl({
    required AppDatabase db,
    ReportsEngine engine = const ReportsEngine(),
  })  : _db = db,
        _engine = engine;

  final AppDatabase _db;
  final ReportsEngine _engine;

  @override
  Future<SalesReport> getSalesReport(
    ReportPeriod period, {
    required String currentAuthUserId,
    required bool canViewAllSales,
  }) async {
    final query = _db.select(_db.sales)
      ..where((s) => s.saleDate.isBetweenValues(period.start, _endOfDay(period.end)));
    // Employee data isolation — see this method's own interface doc
    // comment.
    if (!canViewAllSales) {
      query.where((s) => s.cashierUserId.equals(currentAuthUserId));
    }
    final sales = await query.get();

    final saleIds = sales.map((s) => s.localId).toSet();
    // **Bug fix (void/refund audit):** a voided or refunded sale used to
    // be counted here exactly as if it were still valid — voiding never
    // touches the Sales row itself (see SaleReversalAdjustments' own
    // doc comment for the full trace). A voided sale now contributes
    // nothing to any total below; a genuine (non-void) refund nets out
    // only the refunded amount/quantity, leaving the rest of a partial
    // refund counted normally.
    final adjustments = await SaleReversalAdjustments.load(_db, saleIds);
    final validSales = sales.where((s) => !adjustments.isVoided(s.localId)).toList();

    final totalRevenue = validSales.fold<double>(0, (s, r) => s + adjustments.netRevenue(r));
    // Discount/tax are only zeroed out for a fully voided sale (the
    // whole transaction is excluded); a partial refund does not
    // prorate these — no business rule for that exists in this schema,
    // and inventing one silently would be exactly the kind of
    // unrequested distortion Decision 27 (finance_stats.dart) warns
    // against for cost data. Flagged here rather than done quietly.
    final totalDiscount = validSales.fold<double>(0, (s, r) => s + r.discount);
    final totalTax = validSales.fold<double>(0, (s, r) => s + r.tax);

    final byMethod = <String, List<double>>{}; // method -> [total, count]
    final byHour = <int, List<double>>{};
    for (final sale in validSales) {
      final net = adjustments.netRevenue(sale);
      if (net <= 0) continue; // fully refunded, non-void — nothing left to attribute
      final method = sale.paymentMethod ?? 'Unspecified';
      byMethod.putIfAbsent(method, () => [0, 0]);
      byMethod[method]![0] += net;
      byMethod[method]![1] += 1;

      final hour = sale.saleDate.hour;
      byHour.putIfAbsent(hour, () => [0, 0]);
      byHour[hour]![0] += net;
      byHour[hour]![1] += 1;
    }

    // Top products by revenue — joins sale items for sales in range.
    // `items` is also reused below for the transactions drill-down's
    // per-sale purchased-quantity count, rather than querying twice.
    final productTotals = <String, List<num>>{}; // productLocalId -> [qty, revenue]
    var items = <SaleItemRow>[];
    if (saleIds.isNotEmpty) {
      items = await (_db.select(_db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
      for (final item in items) {
        final productId = item.productLocalId;
        if (productId == null) continue;
        if (adjustments.isVoided(item.saleLocalId)) continue;
        final refunded = adjustments.refundedItemsFor(item.saleLocalId)[productId];
        final netQty = item.quantity - (refunded?.quantity ?? 0);
        final netRevenue = item.unitPrice * item.quantity - (refunded?.amount ?? 0);
        if (netQty <= 0) continue;
        productTotals.putIfAbsent(productId, () => [0, 0]);
        productTotals[productId]![0] += netQty;
        productTotals[productId]![1] += netRevenue < 0 ? 0 : netRevenue;
      }
    }
    final topProducts = <TopProduct>[];
    for (final entry in productTotals.entries) {
      final product = await (_db.select(_db.products)..where((p) => p.localId.equals(entry.key))).getSingleOrNull();
      topProducts.add(TopProduct(
        productId: entry.key,
        productName: product?.name ?? entry.key,
        quantitySold: entry.value[0].toInt(),
        revenue: entry.value[1].toDouble(),
      ));
    }
    topProducts.sort((a, b) => b.revenue.compareTo(a.revenue));

    final byPaymentMethod = byMethod.entries
        .map((e) => SalesByPaymentMethod(method: e.key, total: e.value[0], count: e.value[1].toInt()))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final byHourList = byHour.entries.map((e) => SalesByHour(hour: e.key, total: e.value[0], count: e.value[1].toInt())).toList()
      ..sort((a, b) => a.hour.compareTo(b.hour));
    final top10 = topProducts.take(10).toList();

    // The drill-down list intentionally still lists every sale in
    // range, voided/refunded ones included — that screen's whole job
    // is showing what happened, status label and all (see
    // SaleRecordStatus), unlike the aggregates above which report only
    // what's still valid.
    final transactions = await _buildSaleRecords(sales, items, saleIds);

    return SalesReport(
      period: period,
      totalRevenue: totalRevenue,
      // A voided sale is not a valid completed sale — excluded from
      // the count, same as from revenue. A partially/fully-refunded
      // (non-void) sale still happened as a transaction, so it still
      // counts here even though its revenue contribution above may now
      // be zero.
      totalSalesCount: validSales.length,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      byPaymentMethod: byPaymentMethod,
      byHour: byHourList,
      topProducts: top10,
      transactions: transactions,
      insights: _engine.salesInsights(byPaymentMethod: byPaymentMethod, byHour: byHourList, topProducts: top10),
    );
  }

  /// The Sales report's drill-down — one [SaleRecord] per sale in
  /// [sales], newest first. [saleItems] is the already-fetched sale
  /// items for these same sales (reused, not re-queried) to compute
  /// each sale's purchased quantity; returned quantity and void status
  /// come from one batched query each over ReturnRequests/ReturnItems,
  /// not a per-sale query — the same N+1 mistake
  /// `_sumCostOfGoodsSold` below already had to be fixed for.
  Future<List<SaleRecord>> _buildSaleRecords(
    List<SaleRow> sales,
    List<SaleItemRow> saleItems,
    Set<String> saleIds,
  ) async {
    if (sales.isEmpty) return const [];

    final customerIds = sales.map((s) => s.customerId).whereType<String>().toSet();
    final customerNames = customerIds.isEmpty
        ? <String, String>{}
        : {
            for (final c in await (_db.select(_db.customers)..where((c) => c.localId.isIn(customerIds))).get())
              c.localId: c.name,
          };

    final cashierIds = sales.map((s) => s.cashierUserId).whereType<String>().toSet();
    final cashierNames = cashierIds.isEmpty
        ? <String, String>{}
        : {
            for (final u in await (_db.select(_db.users)..where((u) => u.localId.isIn(cashierIds))).get())
              u.localId: u.fullName,
          };

    final purchasedQtyBySale = <String, int>{};
    for (final item in saleItems) {
      purchasedQtyBySale[item.saleLocalId] = (purchasedQtyBySale[item.saleLocalId] ?? 0) + item.quantity;
    }

    final completedReturns = await (_db.select(_db.returnRequests)
          ..where((r) => r.originalSaleLocalId.isIn(saleIds) & r.status.equals('completed')))
        .get();
    final returnSaleIdByReturnId = {for (final r in completedReturns) r.localId: r.originalSaleLocalId};
    final voidReturnIds = completedReturns.where((r) => r.isVoid).map((r) => r.localId).toSet();
    final returnItemRows = returnSaleIdByReturnId.isEmpty
        ? <ReturnItemRow>[]
        : await (_db.select(_db.returnItems)..where((i) => i.returnLocalId.isIn(returnSaleIdByReturnId.keys))).get();

    final returnedQtyBySale = <String, int>{};
    final voidedSaleIds = <String>{};
    for (final item in returnItemRows) {
      final saleId = returnSaleIdByReturnId[item.returnLocalId];
      if (saleId == null) continue;
      returnedQtyBySale[saleId] = (returnedQtyBySale[saleId] ?? 0) + item.quantity;
      if (voidReturnIds.contains(item.returnLocalId)) voidedSaleIds.add(saleId);
    }

    final records = sales.map((s) {
      final purchased = purchasedQtyBySale[s.localId] ?? 0;
      final returned = returnedQtyBySale[s.localId] ?? 0;
      final status = voidedSaleIds.contains(s.localId)
          ? SaleRecordStatus.voided
          : returned <= 0
              ? SaleRecordStatus.completed
              : (purchased > 0 && returned >= purchased)
                  ? SaleRecordStatus.refunded
                  : SaleRecordStatus.partiallyRefunded;
      final shortId = s.localId.length > 8 ? s.localId.substring(0, 8) : s.localId;
      return SaleRecord(
        saleLocalId: s.localId,
        saleDate: s.saleDate,
        invoiceNumber: s.invoiceNumber ?? 'Sale $shortId',
        customerId: s.customerId,
        customerName: s.customerId != null ? customerNames[s.customerId] : null,
        cashierUserId: s.cashierUserId,
        cashierName: s.cashierUserId != null ? cashierNames[s.cashierUserId] : null,
        paymentMethod: s.paymentMethod,
        total: s.total,
        discount: s.discount,
        status: status,
      );
    }).toList()
      ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

    return records;
  }

  @override
  Future<InventoryReport> getInventoryReport() async {
    final products = await (_db.select(_db.products)..where((p) => p.isActive.equals(true))).get();
    final stockLevels = await _db.select(_db.productStockLevels).get();
    final stockByProduct = <String, int>{};
    for (final level in stockLevels) {
      stockByProduct[level.productLocalId] = (stockByProduct[level.productLocalId] ?? 0) + level.currentStock;
    }

    var totalValue = 0.0;
    var lowStock = 0;
    var outOfStock = 0;
    for (final product in products) {
      final stock = stockByProduct[product.localId] ?? 0;
      totalValue += stock * product.costPrice;
      if (stock <= 0) {
        outOfStock++;
      } else if (stock <= product.lowStockThreshold) {
        lowStock++;
      }
    }

    // "Not sold in 30 days": active products with no SaleItems in the
    // last 30 days. Loaded in memory rather than a correlated SQL
    // subquery — acceptable for the product-catalogue sizes this app
    // targets (small/medium retail, per profile.md), revisit with a
    // proper NOT EXISTS query if that assumption stops holding.
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recentItems = await (_db.select(_db.saleItems).join([
      innerJoin(_db.sales, _db.sales.localId.equalsExp(_db.saleItems.saleLocalId)),
    ])
          ..where(_db.sales.saleDate.isBiggerOrEqualValue(cutoff)))
        .get();
    final recentlySoldIds = recentItems.map((r) => r.readTable(_db.saleItems).productLocalId).toSet();
    final notSold = products.where((p) => !recentlySoldIds.contains(p.localId)).map((p) => p.name).toList();

    // **Bug fix (inventory audit):** these two were hardcoded to 0 with
    // a comment flagging the type split as "not wired in yet" — real
    // data was available in StockMovements the whole time, just never
    // queried. Scoped to the same last-30-days window `notSold` above
    // already uses (this report takes no period of its own — it's a
    // live snapshot, per this class's own header comment — so 30 days
    // is a reasonable "recent activity" window consistent with the one
    // other rolling window this report already shows, not a new
    // business rule invented here). 'sale' movements are deliberately
    // excluded from both buckets — they're a byproduct of a sale, not
    // a manual stock-in/out event, and are already fully represented
    // by the Sales report itself.
    final recentMovements = await (_db.select(_db.stockMovements)
          ..where((m) => m.createdAt.isBiggerOrEqualValue(cutoff)))
        .get();
    var movementsIn = 0;
    var movementsOut = 0;
    for (final m in recentMovements) {
      switch (m.movementType) {
        case 'in':
          movementsIn += m.quantity ?? 0;
        case 'out':
          movementsOut += m.quantity ?? 0;
      }
    }

    return InventoryReport(
      totalStockValue: totalValue,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
      totalProducts: products.length,
      stockMovementsIn: movementsIn,
      stockMovementsOut: movementsOut,
      notSoldInThirtyDays: notSold,
      insights: _engine.inventoryInsights(
        lowStockCount: lowStock,
        outOfStockCount: outOfStock,
        notSoldInThirtyDaysCount: notSold.length,
      ),
    );
  }

  @override
  Future<CustomerReport> getCustomerReport(ReportPeriod period) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) => s.saleDate.isBetweenValues(period.start, _endOfDay(period.end))))
        .get();

    // **Bug fix (void/refund audit):** a customer's "top spender" total
    // used to include whatever they spent on sales later voided or
    // refunded — see SaleReversalAdjustments' own doc comment.
    final adjustments = await SaleReversalAdjustments.load(_db, sales.map((s) => s.localId).toSet());
    final spendByCustomer = <String, double>{};
    for (final sale in sales) {
      final id = sale.customerId;
      if (id == null) continue;
      final net = adjustments.netRevenue(sale);
      if (net <= 0) continue;
      spendByCustomer[id] = (spendByCustomer[id] ?? 0) + net;
    }
    final topCustomers = <TopCustomer>[];
    for (final entry in spendByCustomer.entries) {
      final customer = await (_db.select(_db.customers)..where((c) => c.localId.equals(entry.key))).getSingleOrNull();
      if (customer != null) {
        topCustomers.add(TopCustomer(customerId: customer.localId, customerName: customer.name, totalSpend: entry.value));
      }
    }
    topCustomers.sort((a, b) => b.totalSpend.compareTo(a.totalSpend));

    final allCustomers = await (_db.select(_db.customers)..where((c) => c.deletedAt.isNull())).get();
    final outstanding = allCustomers.fold<double>(0, (s, c) => s + c.outstandingBalance);
    final newCustomers = allCustomers
        .where((c) => !c.createdAt.isBefore(period.start) && !c.createdAt.isAfter(_endOfDay(period.end)))
        .length;

    final top10 = topCustomers.take(10).toList();
    return CustomerReport(
      period: period,
      topCustomers: top10,
      totalOutstandingCredit: outstanding,
      newCustomersThisPeriod: newCustomers,
      insights: _engine.customerInsights(
        newCustomersThisPeriod: newCustomers,
        totalOutstandingCredit: outstanding,
        topCustomers: top10,
      ),
    );
  }

  @override
  Future<FinanceReport> getFinanceReport(ReportPeriod period) async {
    final revenue = await _sumSalesRevenue(period.start, period.end);
    final costOfGoodsSold = await _sumCostOfGoodsSold(period.start, period.end);
    final expenses = await _sumExpenses(period.start, period.end);
    // Bug fix (business-logic audit): this used to be `revenue -
    // expenses`, omitting cost of goods sold entirely — the "Net
    // profit" figure on the Finance tab (the only screen that calls
    // this method) overstated real profit by the full COGS of every
    // sale in the period. The correct, COGS-aware formula already
    // existed in FinanceStatsRepositoryImpl.getProfitLoss — fully
    // implemented, DI-wired via financeStatsRepositoryProvider — but
    // had zero callers anywhere in the UI (confirmed by grep). Rather
    // than switch this screen onto that separate repository (a larger
    // change touching DI/provider wiring for a fix that doesn't need
    // it), this brings the same correct formula here, so the one
    // number the app actually shows a shop owner is right.
    final netProfit = revenue - costOfGoodsSold - expenses;

    final prev = period.previous;
    final prevRevenue = await _sumSalesRevenue(prev.start, prev.end);
    final prevCostOfGoodsSold = await _sumCostOfGoodsSold(prev.start, prev.end);
    final prevExpenses = await _sumExpenses(prev.start, prev.end);
    final prevNetProfit = prevRevenue - prevCostOfGoodsSold - prevExpenses;
    final hasPrevData = prevRevenue > 0 || prevExpenses > 0;

    final expenseRows = await (_db.select(_db.expenses)
          ..where((e) => e.expenseDate.isBetweenValues(period.start, _endOfDay(period.end))))
        .get();
    // Bug fix found while wiring the Finance tab's breakdown display up
    // to real data for the first time (gap-closure pass — "Reports
    // drill-down"): this used to key `byCategory` by `e.categoryId`
    // itself (a ULID) and pass that straight through as
    // `ExpenseCategoryTotal.category` — since nothing in the UI ever
    // rendered `expenseBreakdown` before now, a raw id masquerading as
    // a display label went unnoticed. Resolved against
    // ExpenseCategories the same way `getSalesReport`'s topProducts
    // loop resolves a product name from its id, just batched into one
    // query up front rather than one per row.
    final categoryNamesById = {
      for (final c in await _db.select(_db.expenseCategories).get()) c.localId: c.name,
    };
    final byCategory = <String, double>{};
    for (final e in expenseRows) {
      final cat = e.categoryId != null ? (categoryNamesById[e.categoryId] ?? 'Other') : 'Uncategorized';
      byCategory[cat] = (byCategory[cat] ?? 0) + e.amount;
    }
    final breakdown = byCategory.entries.map((e) => ExpenseCategoryTotal(category: e.key, total: e.value)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return FinanceReport(
      period: period,
      totalRevenue: revenue,
      totalCostOfGoodsSold: costOfGoodsSold,
      totalExpenses: expenses,
      netProfit: netProfit,
      previousPeriodNetProfit: hasPrevData ? prevNetProfit : null,
      expenseBreakdown: breakdown,
      insights: _engine.financeInsights(netProfit: netProfit, previousNetProfit: hasPrevData ? prevNetProfit : null),
    );
  }

  Future<double> _sumSalesRevenue(DateTime start, DateTime end) async {
    final sales = await (_db.select(_db.sales)..where((s) => s.saleDate.isBetweenValues(start, _endOfDay(end)))).get();
    // **Bug fix (void/refund audit):** see SaleReversalAdjustments' own
    // doc comment — a voided or refunded sale used to contribute its
    // full `total` here regardless.
    final adjustments = await SaleReversalAdjustments.load(_db, sales.map((s) => s.localId).toSet());
    final salesTotal = sales.fold<double>(0, (s, r) => s + adjustments.netRevenue(r));
    final income = await (_db.select(_db.incomeRecords)..where((i) => i.incomeDate.isBetweenValues(start, _endOfDay(end)))).get();
    final incomeTotal = income.fold<double>(0, (s, r) => s + r.amount);
    return salesTotal + incomeTotal;
  }

  /// Same join/sum FinanceStatsRepositoryImpl.getProfitLoss already
  /// uses — Sales in range, joined to their SaleItems, summing
  /// `costPriceAtSale * quantity`. `costPriceAtSale` is captured at the
  /// moment each item was added to cart (see DraftCartRepositoryImpl.
  /// addItem), so this is honest even if a product's cost price is
  /// edited later; a Quick Sale line always contributes 0 here (no
  /// catalog product, so no known cost — see that field's own doc
  /// comment), same as it correctly does everywhere else in this app.
  ///
  /// **Bug fix (void/refund audit):** a voided sale's items used to be
  /// summed into cost of goods sold exactly like any other sale's — the
  /// business no longer holds that inventory cost against a sale that
  /// never should have counted. See SaleReversalAdjustments' own doc
  /// comment for the full trace and for how a partial (non-void) refund
  /// nets out only the refunded quantity's cost, not the whole sale's.
  Future<double> _sumCostOfGoodsSold(DateTime start, DateTime end) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) => s.saleDate.isBetweenValues(start, _endOfDay(end))))
        .get();
    final saleIds = sales.map((s) => s.localId).toSet();
    if (saleIds.isEmpty) return 0.0;
    // One batched query, not one per sale (the exact N+1 shape
    // getSalesReport's topProducts computation already avoided —
    // this method just hadn't been brought in line with it yet).
    final items = await (_db.select(_db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
    final adjustments = await SaleReversalAdjustments.load(_db, saleIds);
    final rawCostBySale = <String, double>{};
    for (final item in items) {
      rawCostBySale[item.saleLocalId] = (rawCostBySale[item.saleLocalId] ?? 0) + item.costPriceAtSale * item.quantity;
    }
    return rawCostBySale.entries
        .fold<double>(0.0, (sum, e) => sum + adjustments.netCostOfGoodsSold(e.key, e.value));
  }

  Future<double> _sumExpenses(DateTime start, DateTime end) async {
    final rows = await (_db.select(_db.expenses)..where((e) => e.expenseDate.isBetweenValues(start, _endOfDay(end)))).get();
    return rows.fold<double>(0, (s, r) => s + r.amount);
  }

  @override
  Future<EmployeeReport> getEmployeeReport(ReportPeriod period) async {
    final employees = await (_db.select(_db.employees)..where((e) => e.deletedAt.isNull())).get();

    // **Confirmed bug fix (Reports & Auditability upgrade):** the
    // comment this replaced claimed Sales carried no cashier reference
    // at all — false since schema v4 added Sales.cashierUserId
    // (populated at sale creation, see sale_repository_impl.dart).
    // Verified directly rather than trusted: grepped the table
    // definition and the write site before relying on either.
    //
    // The join key is Employees.authUserId (nullable — not every
    // employee has a login account, see employee.dart's own doc
    // comment), not Employees.id — Sales.cashierUserId references
    // Users.localId, and authUserId is what links an Employee row to
    // that Users row. An employee with no linked account (authUserId
    // null) correctly gets 0/0 here, same as before — there's nothing
    // on any Sale that could point back to them.
    //
    // One batched query for every sale in the period, then grouped by
    // cashier in memory — not one query per employee, the same N+1
    // shape _sumCostOfGoodsSold above just got fixed for.
    final sales = await (_db.select(_db.sales)
          ..where((s) => s.saleDate.isBetweenValues(period.start, _endOfDay(period.end))))
        .get();
    // **Bug fix (void/refund audit):** salesTotalByCashier used to sum
    // `sale.total` unconditionally, same as every other aggregate this
    // audit found — see SaleReversalAdjustments' own doc comment. Not
    // currently rendered anywhere in the Team tab, but fixed at the
    // source so a future UI addition doesn't silently inherit the bug.
    final adjustments = await SaleReversalAdjustments.load(_db, sales.map((s) => s.localId).toSet());
    final salesTotalByCashier = <String, double>{};
    final salesCountByCashier = <String, int>{};
    for (final sale in sales) {
      final cashierId = sale.cashierUserId;
      if (cashierId == null) continue;
      if (adjustments.isVoided(sale.localId)) continue;
      salesTotalByCashier[cashierId] = (salesTotalByCashier[cashierId] ?? 0) + adjustments.netRevenue(sale);
      salesCountByCashier[cashierId] = (salesCountByCashier[cashierId] ?? 0) + 1;
    }

    final performance = <EmployeePerformance>[];
    for (final emp in employees) {
      final attendance = await (_db.select(_db.attendanceRecords)
            ..where((a) =>
                a.employeeId.equals(emp.id) &
                a.date.isBetweenValues(period.start, _endOfDay(period.end))))
          .get();
      final domainRecords = attendance.map((r) => r.toDomain()).toList();
      var present = 0, absent = 0, late = 0;
      for (final r in domainRecords) {
        switch (r.status) {
          case AttendanceStatus.present:
            present++;
          case AttendanceStatus.absent:
            absent++;
          case AttendanceStatus.late:
            late++;
        }
      }
      final authUserId = emp.authUserId;
      performance.add(EmployeePerformance(
        employeeId: emp.id,
        employeeName: emp.fullName,
        salesTotal: authUserId != null ? (salesTotalByCashier[authUserId] ?? 0) : 0,
        salesCount: authUserId != null ? (salesCountByCashier[authUserId] ?? 0) : 0,
        daysPresent: present,
        daysAbsent: absent,
        daysLate: late,
      ));
    }

    return EmployeeReport(
      period: period,
      performance: performance,
      insights: _engine.employeeInsights(performance),
    );
  }

  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
