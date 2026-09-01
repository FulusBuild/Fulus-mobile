import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/local/database/tables/employee_tables.dart';
import 'package:fulus_mobile/data/repositories/reports_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/report.dart';

/// No test file existed for ReportsRepositoryImpl before this one — that
/// gap is exactly why the bug below shipped unnoticed while its correct
/// sibling (FinanceStatsRepositoryImpl, covered by
/// finance_stats_repository_test.dart) was already tested.
void main() {
  late AppDatabase db;
  late ReportsRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ReportsRepositoryImpl(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertLocation(String id) async {
    await db.into(db.locations).insert(
          LocationsCompanion.insert(
            localId: id,
            name: 'Test Location',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  Future<void> insertCompletedSale({
    required String localId,
    required String locationId,
    required DateTime saleDate,
    required double total,
    required double amountPaid,
    required List<({double costPriceAtSale, int quantity, String? productId})> items,
    String? cashierUserId,
    String? customerId,
    String? invoiceNumber,
    String? paymentMethod,
    double discount = 0,
  }) async {
    await db.into(db.sales).insert(
          SalesCompanion.insert(
            localId: localId,
            clientReference: localId,
            locationId: locationId,
            saleDate: saleDate,
            subtotal: total,
            total: total,
            amountPaid: Value(amountPaid),
            discount: Value(discount),
            cashierUserId: Value(cashierUserId),
            customerId: Value(customerId),
            invoiceNumber: Value(invoiceNumber),
            paymentMethod: Value(paymentMethod),
            createdAt: saleDate,
            updatedAt: saleDate,
            syncStatus: SyncStatus.settled,
          ),
        );
    for (var i = 0; i < items.length; i++) {
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              localId: '$localId-item-$i',
              saleLocalId: localId,
              productLocalId: Value(items[i].productId),
              quantity: items[i].quantity,
              unitPrice: 100,
              costPriceAtSale: items[i].costPriceAtSale,
            ),
          );
    }
  }

  Future<void> insertProduct(String localId) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            localId: localId,
            name: localId,
            sku: 'SKU-$localId',
            costPrice: 40,
            sellingPrice: 100,
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  Future<void> insertUser(String localId, String fullName) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.users).insert(
          UsersCompanion.insert(
            localId: localId,
            username: Value(localId),
            email: Value('$localId@test.local'),
            fullName: fullName,
            hashedPassword: const Value('x'),
            passwordSalt: const Value('x'),
            role: AuthRole.employee,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// A completed return/void against [saleLocalId], one line covering
  /// [quantity] of [productId] — inserted directly (not via
  /// ReturnRepositoryImpl, which this file doesn't construct) since
  /// only the resulting rows matter for what ReportsRepositoryImpl
  /// reads.
  Future<void> insertCompletedReturn({
    required String localId,
    required String saleLocalId,
    required String productId,
    required int quantity,
    bool isVoid = false,
  }) async {
    final now = DateTime(2026, 1, 1);
    await db.into(db.returnRequests).insert(
          ReturnRequestsCompanion.insert(
            localId: localId,
            originalSaleLocalId: saleLocalId,
            status: 'completed',
            returnReason: 'Test',
            refundAmount: 0,
            refundMethod: 'cash',
            isVoid: Value(isVoid),
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        );
    await db.into(db.returnItems).insert(
          ReturnItemsCompanion.insert(
            localId: '$localId-item',
            returnLocalId: localId,
            productLocalId: productId,
            quantity: quantity,
          ),
        );
  }

  Future<void> insertExpense({
    required String localId,
    required String locationId,
    required double amount,
    required DateTime date,
  }) async {
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            localId: localId,
            locationId: locationId,
            description: 'Test expense',
            amount: amount,
            expenseDate: date,
            createdAt: date,
            updatedAt: date,
            syncStatus: SyncStatus.settled,
          ),
        );
  }

  group('getFinanceReport — net profit (business-logic audit bug fix)', () {
    test(
        'nets cost of goods sold, not just expenses — the confirmed bug: '
        'this used to be revenue - expenses only', () async {
      await insertLocation('loc-1');
      // Same scenario as finance_stats_repository_test.dart's
      // 'net profit nets cost of goods sold and expenses from revenue'
      // test, so the two repositories can be checked against each
      // other directly: revenue 1000, COGS 300 (5 units @ cost 60),
      // expenses 200.
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5, productId: null)],
      );
      await insertExpense(
        localId: 'expense-1',
        locationId: 'loc-1',
        amount: 200,
        date: DateTime(2026, 1, 10),
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalRevenue, 1000);
      expect(report.totalCostOfGoodsSold, 300);
      expect(report.totalExpenses, 200);
      expect(report.grossProfit, 700);
      // Before the fix this returned 800 (1000 - 200, COGS never
      // subtracted) — the exact defect this pins down. Matches
      // FinanceStatsRepositoryImpl.getProfitLoss's netProfit for the
      // identical seeded data.
      expect(report.netProfit, 500);
    });

    test('a Quick Sale line (no catalog product, cost 0) correctly '
        'contributes nothing to cost of goods sold', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 500,
        amountPaid: 500,
        items: [(costPriceAtSale: 0, quantity: 3, productId: null)],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalCostOfGoodsSold, 0);
      expect(report.netProfit, 500);
    });

    test('multiple line items on one sale all contribute to cost of '
        'goods sold', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [
          (costPriceAtSale: 60, quantity: 5, productId: null), // 300
          (costPriceAtSale: 40, quantity: 2, productId: null), // 80
        ],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalCostOfGoodsSold, 380);
    });

    test('the previous-period comparison is COGS-aware too, so the '
        'trend percentage does not compare a corrected figure against '
        'an uncorrected one', () async {
      await insertLocation('loc-1');
      // Current period: revenue 1000, COGS 300, expenses 0 -> profit 700.
      await insertCompletedSale(
        localId: 'sale-current',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 2, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5, productId: null)],
      );
      // Previous period (same length: Jan 1-31): revenue 1000, COGS
      // 500 (5 units @ cost 100), expenses 0 -> profit 500.
      await insertCompletedSale(
        localId: 'sale-previous',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 100, quantity: 5, productId: null)],
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 2, 1),
          end: DateTime(2026, 2, 28),
        ),
      );

      expect(report.netProfit, 700);
      // Before the fix, the current period's 800 (COGS omitted) would
      // have been compared against a previous period that (by the same
      // bug) was also COGS-omitted, i.e. 1000 — masking the bug from a
      // trend-only test. Comparing the two CORRECT figures: 700 vs 500
      // previous is a +40% change, not whatever the uncorrected pair
      // would have produced.
      expect(report.previousPeriodNetProfit, 500);
      expect(report.profitTrendPercent, closeTo(40.0, 0.001));
    });

    test('zero sales and zero expenses in range produces a zero net '
        'profit, not a null or error', () async {
      await insertLocation('loc-1');

      final report = await repository.getFinanceReport(
        ReportPeriod(
          kind: ReportPeriodKind.custom,
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );

      expect(report.totalRevenue, 0);
      expect(report.totalCostOfGoodsSold, 0);
      expect(report.totalExpenses, 0);
      expect(report.netProfit, 0);
      expect(report.previousPeriodNetProfit, isNull);
    });
  });

  group('getSalesReport — transactions drill-down', () {
    test('one record per sale, newest first', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
      );
      await insertCompletedSale(
        localId: 'sale-2',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 20),
        total: 2000,
        amountPaid: 2000,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      expect(report.transactions, hasLength(2));
      expect(report.transactions.first.saleLocalId, 'sale-2'); // newest first
      expect(report.transactions.last.saleLocalId, 'sale-1');
    });

    test('resolves customer and cashier names, and falls back to a '
        'short reference when there is no invoice number', () async {
      await insertLocation('loc-1');
      await insertUser('cashier-1', 'Amaka Okafor');
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              localId: 'customer-1',
              name: 'Tunde Bakare',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              syncStatus: SyncStatus.settled,
            ),
          );
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
        cashierUserId: 'cashier-1',
        customerId: 'customer-1',
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      final record = report.transactions.single;
      expect(record.cashierName, 'Amaka Okafor');
      expect(record.customerName, 'Tunde Bakare');
      expect(record.invoiceNumber, 'Sale sale-1'); // 'sale-1' is <=8 chars, used whole
    });

    test('a sale with no completed return is "completed"', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      expect(report.transactions.single.status, SaleRecordStatus.completed);
    });

    test('a fully-returned sale is "refunded"; a voided one is "voided", '
        'not conflated with a genuine return', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-refunded',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 2, productId: 'product-a')],
      );
      await insertCompletedReturn(
        localId: 'return-1',
        saleLocalId: 'sale-refunded',
        productId: 'product-a',
        quantity: 2, // all of it
        isVoid: false,
      );
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 6),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 2, productId: 'product-a')],
      );
      await insertCompletedReturn(
        localId: 'return-2',
        saleLocalId: 'sale-voided',
        productId: 'product-a',
        quantity: 2,
        isVoid: true,
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      final refunded = report.transactions.firstWhere((t) => t.saleLocalId == 'sale-refunded');
      final voided = report.transactions.firstWhere((t) => t.saleLocalId == 'sale-voided');
      expect(refunded.status, SaleRecordStatus.refunded);
      expect(voided.status, SaleRecordStatus.voided);
    });

    test('a partially-returned sale is "partiallyRefunded"', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 4, productId: 'product-a')],
      );
      await insertCompletedReturn(
        localId: 'return-1',
        saleLocalId: 'sale-1',
        productId: 'product-a',
        quantity: 1, // 1 of 4 — partial
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      expect(report.transactions.single.status, SaleRecordStatus.partiallyRefunded);
    });
  });

  group('getSalesReport — void/refund audit (bug fix)', () {
    test('a voided sale contributes nothing to revenue, count, top '
        'products, or payment-method/hour breakdowns', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-good',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5, 10),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 40, quantity: 2, productId: 'product-a')],
        paymentMethod: 'cash',
      );
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 6, 14),
        total: 500,
        amountPaid: 500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: 'product-a')],
        paymentMethod: 'cash',
      );
      await insertCompletedReturn(
        localId: 'return-void',
        saleLocalId: 'sale-voided',
        productId: 'product-a',
        quantity: 1,
        isVoid: true,
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      // Before the fix: totalRevenue 1500, count 2 — the voided sale
      // counted as if it were still valid.
      expect(report.totalRevenue, 1000);
      expect(report.totalSalesCount, 1);
      expect(report.topProducts.single.quantitySold, 2);
      expect(report.topProducts.single.revenue, 200); // 2 * unitPrice(100)
      expect(report.byPaymentMethod.single.total, 1000);
      expect(report.byPaymentMethod.single.count, 1);
      expect(report.byHour.single.total, 1000);
    });

    test('a partially-refunded sale nets the refunded amount/quantity '
        'out of revenue and top products, but still counts as one sale',
        () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5, 10),
        total: 400,
        amountPaid: 400,
        items: const [(costPriceAtSale: 40, quantity: 4, productId: 'product-a')],
        paymentMethod: 'cash',
      );
      // 1 of 4 units returned (non-void) — unitPrice was 100 (see
      // insertCompletedSale's fixed 100/unit), so 100 comes back out.
      await insertCompletedReturn(
        localId: 'return-1',
        saleLocalId: 'sale-1',
        productId: 'product-a',
        quantity: 1,
      );

      final report = await repository.getSalesReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
        currentAuthUserId: 'u1',
        canViewAllSales: true,
      );

      expect(report.totalRevenue, 300); // 400 - 100 refunded
      expect(report.totalSalesCount, 1); // still one real transaction
      expect(report.topProducts.single.quantitySold, 3);
      expect(report.topProducts.single.revenue, 300);
    });
  });

  group('getFinanceReport — void/refund audit (bug fix)', () {
    test('a voided sale contributes nothing to revenue or cost of goods '
        'sold', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1000,
        amountPaid: 1000,
        items: const [(costPriceAtSale: 60, quantity: 2, productId: 'product-a')],
      );
      await insertCompletedReturn(
        localId: 'return-void',
        saleLocalId: 'sale-voided',
        productId: 'product-a',
        quantity: 2,
        isVoid: true,
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      // Before the fix: revenue 1000, COGS 120 — the voided sale
      // counted as if it were a normal, valid one.
      expect(report.totalRevenue, 0);
      expect(report.totalCostOfGoodsSold, 0);
    });

    test('a partially-refunded sale nets the refunded quantity\'s cost '
        'out of cost of goods sold', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 400,
        amountPaid: 400,
        items: const [(costPriceAtSale: 60, quantity: 4, productId: 'product-a')],
      );
      await insertCompletedReturn(
        localId: 'return-1',
        saleLocalId: 'sale-1',
        productId: 'product-a',
        quantity: 1, // 1 of 4 returned
      );

      final report = await repository.getFinanceReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      expect(report.totalRevenue, 300); // 400 - 100 (1 unit @ 100)
      expect(report.totalCostOfGoodsSold, 180); // (4-1) units @ cost 60
    });
  });

  group('getCustomerReport — void/refund audit (bug fix)', () {
    test('a customer\'s top-spender total excludes a voided sale and '
        'nets a partial refund', () async {
      await insertLocation('loc-1');
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              localId: 'customer-1',
              name: 'Tunde Bakare',
              createdAt: DateTime(2025, 1, 1),
              updatedAt: DateTime(2025, 1, 1),
              syncStatus: SyncStatus.settled,
            ),
          );
      await insertProduct('product-a');
      await insertCompletedSale(
        localId: 'sale-good',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 300,
        amountPaid: 300,
        items: const [(costPriceAtSale: 40, quantity: 3, productId: 'product-a')],
        customerId: 'customer-1',
      );
      await insertCompletedReturn(
        localId: 'return-1',
        saleLocalId: 'sale-good',
        productId: 'product-a',
        quantity: 1, // partial: 100 comes back out
      );
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 6),
        total: 500,
        amountPaid: 500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: 'product-a')],
        customerId: 'customer-1',
      );
      await insertCompletedReturn(
        localId: 'return-void',
        saleLocalId: 'sale-voided',
        productId: 'product-a',
        quantity: 1,
        isVoid: true,
      );

      final report = await repository.getCustomerReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      // Before the fix: 800 (300 + 500, both sales counted in full).
      expect(report.topCustomers.single.totalSpend, 200); // 300 - 100
    });
  });

  group('getEmployeeReport — void/refund audit (bug fix)', () {
    test('a voided sale is excluded from a cashier\'s attributed sales '
        'total and count', () async {
      await insertLocation('loc-1');
      await insertUser('user-1', 'Amaka Okafor');
      await insertProduct('product-a');
      await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              id: 'emp-1',
              fullName: 'Amaka Okafor',
              authUserId: const Value('user-1'),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1500,
        amountPaid: 1500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: 'product-a')],
        cashierUserId: 'user-1',
      );
      await insertCompletedReturn(
        localId: 'return-void',
        saleLocalId: 'sale-voided',
        productId: 'product-a',
        quantity: 1,
        isVoid: true,
      );

      final report = await repository.getEmployeeReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      final perf = report.performance.single;
      expect(perf.salesTotal, 0);
      expect(perf.salesCount, 0);
    });
  });

  group('getEmployeeReport — attendance insight coverage (bug fix)', () {
    test('the team-attendance insight names how much of the roster was '
        'actually tracked when it is not everyone', () async {
      await insertLocation('loc-1');
      await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              id: 'emp-1',
              fullName: 'Tracked Employee',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              id: 'emp-2',
              fullName: 'Untracked Employee',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await db.into(db.attendanceRecords).insert(
            AttendanceRecordsCompanion.insert(
              id: 'att-1',
              employeeId: 'emp-1',
              date: DateTime(2026, 1, 5),
              status: AttendanceStatusValue.present,
            ),
          );

      final report = await repository.getEmployeeReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      // Before the fix, this read simply "Team attendance was 100% this
      // period." — easy to misread as the whole team, when only 1 of 2
      // employees has any attendance record at all this period.
      expect(
        report.insights.single.text,
        'Team attendance was 100% this period (based on 1 of 2 '
        'employees with attendance recorded).',
      );
    });
  });

  group('getInventoryReport — stock movements (bug fix)', () {
    test('stockMovementsIn/Out reflect real StockMovements rows, not a '
        'hardcoded 0', () async {
      await insertLocation('loc-1');
      await insertProduct('product-a');
      final now = DateTime.now();
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              localId: 'move-in',
              productLocalId: 'product-a',
              locationId: 'loc-1',
              movementType: 'in',
              quantity: const Value(10),
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              localId: 'move-out',
              productLocalId: 'product-a',
              locationId: 'loc-1',
              movementType: 'out',
              quantity: const Value(4),
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );
      // Excluded: a sale-triggered movement, and an adjustment.
      await db.into(db.stockMovements).insert(
            StockMovementsCompanion.insert(
              localId: 'move-sale',
              productLocalId: 'product-a',
              locationId: 'loc-1',
              movementType: 'sale',
              quantity: const Value(1),
              createdAt: now,
              updatedAt: now,
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getInventoryReport();

      expect(report.stockMovementsIn, 10);
      expect(report.stockMovementsOut, 4);
    });
  });

  group('getEmployeeReport — sales figures (bug fix)', () {
    test('attributes sales to the employee whose linked account rang '
        'them up', () async {
      await insertLocation('loc-1');
      await insertUser('user-1', 'Amaka Okafor');
      await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              id: 'emp-1',
              fullName: 'Amaka Okafor',
              authUserId: const Value('user-1'),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1500,
        amountPaid: 1500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
        cashierUserId: 'user-1',
      );
      await insertCompletedSale(
        localId: 'sale-2',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 6),
        total: 500,
        amountPaid: 500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
        cashierUserId: 'user-1',
      );

      final report = await repository.getEmployeeReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      final perf = report.performance.single;
      expect(perf.salesTotal, 2000);
      expect(perf.salesCount, 2);
    });

    test('an employee with no linked login account correctly shows 0, '
        'not misattributed sales', () async {
      await insertLocation('loc-1');
      await insertUser('user-1', 'Amaka Okafor');
      await db.into(db.employees).insert(
            EmployeesCompanion.insert(
              id: 'emp-1',
              fullName: 'Chidi Eze', // no authUserId — never set up a login
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 5),
        total: 1500,
        amountPaid: 1500,
        items: const [(costPriceAtSale: 40, quantity: 1, productId: null)],
        cashierUserId: 'user-1', // rung up by a DIFFERENT, unrelated account
      );

      final report = await repository.getEmployeeReport(
        ReportPeriod(kind: ReportPeriodKind.custom, start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 31)),
      );

      final perf = report.performance.single;
      expect(perf.salesTotal, 0);
      expect(perf.salesCount, 0);
    });
  });
}
