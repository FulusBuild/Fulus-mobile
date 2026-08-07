import 'package:drift/drift.dart';

import '../../domain/entities/employee.dart';
import '../../domain/entities/report.dart';
import '../../domain/repositories/reports_repository.dart';
import '../../domain/usecases/reports_engine.dart';
import '../local/database/database.dart';
import 'employee_mapper.dart';

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
  Future<SalesReport> getSalesReport(ReportPeriod period) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) => s.saleDate.isBetweenValues(period.start, _endOfDay(period.end))))
        .get();

    final totalRevenue = sales.fold<double>(0, (s, r) => s + r.total);
    final totalDiscount = sales.fold<double>(0, (s, r) => s + r.discount);
    final totalTax = sales.fold<double>(0, (s, r) => s + r.tax);

    final byMethod = <String, List<double>>{}; // method -> [total, count]
    final byHour = <int, List<double>>{};
    for (final sale in sales) {
      final method = sale.paymentMethod ?? 'Unspecified';
      byMethod.putIfAbsent(method, () => [0, 0]);
      byMethod[method]![0] += sale.total;
      byMethod[method]![1] += 1;

      final hour = sale.saleDate.hour;
      byHour.putIfAbsent(hour, () => [0, 0]);
      byHour[hour]![0] += sale.total;
      byHour[hour]![1] += 1;
    }

    // Top products by revenue — joins sale items for sales in range.
    final saleIds = sales.map((s) => s.localId).toSet();
    final productTotals = <String, List<num>>{}; // productLocalId -> [qty, revenue]
    if (saleIds.isNotEmpty) {
      final items = await (_db.select(_db.saleItems)..where((i) => i.saleLocalId.isIn(saleIds))).get();
      for (final item in items) {
        productTotals.putIfAbsent(item.productLocalId, () => [0, 0]);
        productTotals[item.productLocalId]![0] += item.quantity;
        productTotals[item.productLocalId]![1] += item.unitPrice * item.quantity;
      }
    }
    final topProducts = <TopProduct>[];
    for (final entry in productTotals.entries) {
      final product = await (_db.select(_db.products)..where((p) => p.localId.equals(entry.key))).getSingleOrNull();
      topProducts.add(TopProduct(
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

    return SalesReport(
      period: period,
      totalRevenue: totalRevenue,
      totalSalesCount: sales.length,
      totalDiscount: totalDiscount,
      totalTax: totalTax,
      byPaymentMethod: byPaymentMethod,
      byHour: byHourList,
      topProducts: top10,
      insights: _engine.salesInsights(byPaymentMethod: byPaymentMethod, byHour: byHourList, topProducts: top10),
    );
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

    return InventoryReport(
      totalStockValue: totalValue,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
      totalProducts: products.length,
      stockMovementsIn: 0, // see INTEGRATION.md — StockMovements type split not wired in yet
      stockMovementsOut: 0,
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

    final spendByCustomer = <String, double>{};
    for (final sale in sales) {
      final id = sale.customerId;
      if (id == null) continue;
      spendByCustomer[id] = (spendByCustomer[id] ?? 0) + sale.total;
    }
    final topCustomers = <TopCustomer>[];
    for (final entry in spendByCustomer.entries) {
      final customer = await (_db.select(_db.customers)..where((c) => c.localId.equals(entry.key))).getSingleOrNull();
      if (customer != null) {
        topCustomers.add(TopCustomer(customerName: customer.name, totalSpend: entry.value));
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
    final expenses = await _sumExpenses(period.start, period.end);
    final netProfit = revenue - expenses;

    final prev = period.previous;
    final prevRevenue = await _sumSalesRevenue(prev.start, prev.end);
    final prevExpenses = await _sumExpenses(prev.start, prev.end);
    final prevNetProfit = prevRevenue - prevExpenses;
    final hasPrevData = prevRevenue > 0 || prevExpenses > 0;

    final expenseRows = await (_db.select(_db.expenses)
          ..where((e) => e.expenseDate.isBetweenValues(period.start, _endOfDay(period.end))))
        .get();
    final byCategory = <String, double>{};
    for (final e in expenseRows) {
      final cat = e.categoryId ?? 'Uncategorized';
      byCategory[cat] = (byCategory[cat] ?? 0) + e.amount;
    }
    final breakdown = byCategory.entries.map((e) => ExpenseCategoryTotal(category: e.key, total: e.value)).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return FinanceReport(
      period: period,
      totalRevenue: revenue,
      totalExpenses: expenses,
      netProfit: netProfit,
      previousPeriodNetProfit: hasPrevData ? prevNetProfit : null,
      expenseBreakdown: breakdown,
      insights: _engine.financeInsights(netProfit: netProfit, previousNetProfit: hasPrevData ? prevNetProfit : null),
    );
  }

  Future<double> _sumSalesRevenue(DateTime start, DateTime end) async {
    final sales = await (_db.select(_db.sales)..where((s) => s.saleDate.isBetweenValues(start, _endOfDay(end)))).get();
    final salesTotal = sales.fold<double>(0, (s, r) => s + r.total);
    final income = await (_db.select(_db.incomeRecords)..where((i) => i.incomeDate.isBetweenValues(start, _endOfDay(end)))).get();
    final incomeTotal = income.fold<double>(0, (s, r) => s + r.amount);
    return salesTotal + incomeTotal;
  }

  Future<double> _sumExpenses(DateTime start, DateTime end) async {
    final rows = await (_db.select(_db.expenses)..where((e) => e.expenseDate.isBetweenValues(start, _endOfDay(end)))).get();
    return rows.fold<double>(0, (s, r) => s + r.amount);
  }

  @override
  Future<EmployeeReport> getEmployeeReport(ReportPeriod period) async {
    final employees = await (_db.select(_db.employees)..where((e) => e.deletedAt.isNull())).get();

    // Sales carries no cashier/employee reference in the checkpoint
    // schema this was written against (same gap noted in
    // receipt_repository_impl.dart) — per-employee sales figures are
    // therefore 0 until Sales gains that column; attendance figures
    // below are unaffected and fully real.
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
      performance.add(EmployeePerformance(
        employeeId: emp.id,
        employeeName: emp.fullName,
        salesTotal: 0,
        salesCount: 0,
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
