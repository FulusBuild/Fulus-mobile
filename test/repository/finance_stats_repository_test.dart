import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/customer_credit_repository_impl.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:fulus_mobile/data/repositories/finance_stats_repository_impl.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FinanceStatsRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FinanceStatsRepositoryImpl(
      db: db,
      customerCreditRepository: CustomerCreditRepositoryImpl(db: db, syncQueue: SyncQueue(db)),
    );
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
    required List<({double costPriceAtSale, int quantity})> items,
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
              quantity: items[i].quantity,
              unitPrice: 100,
              costPriceAtSale: items[i].costPriceAtSale,
            ),
          );
    }
  }

  group('getProfitLoss — cost data completeness', () {
    test('1.0 when every sold unit has a recorded cost price', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5)],
      );

      final report = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.costDataCompleteness, 1.0);
      expect(report.costOfGoodsSold, 300);
    });

    test('partial completeness when some sold units have no cost recorded',
        () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 2000,
        amountPaid: 2000,
        items: [
          (costPriceAtSale: 60, quantity: 5), // 5 units with cost
          (costPriceAtSale: 0, quantity: 5), // 5 units with no cost (Quick Sale)
        ],
      );

      final report = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      // 5 of 10 units had a recorded cost.
      expect(report.costDataCompleteness, 0.5);
      // COGS only reflects the 5 units that had a cost — silently
      // understating true cost, exactly why completeness has to be
      // shown alongside it rather than presented as a precise figure.
      expect(report.costOfGoodsSold, 300);
    });

    test('1.0 (not 0/0) when the range has no sales at all', () async {
      await insertLocation('loc-1');

      final report = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.costDataCompleteness, 1.0);
      expect(report.revenue, 0);
    });

    test('net profit nets cost of goods sold and expenses from revenue',
        () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: [(costPriceAtSale: 60, quantity: 5)],
      );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              localId: 'expense-1',
              locationId: 'loc-1',
              description: 'Rent',
              amount: 200,
              expenseDate: DateTime(2026, 1, 10),
              createdAt: DateTime(2026, 1, 10),
              updatedAt: DateTime(2026, 1, 10),
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.revenue, 1000);
      expect(report.costOfGoodsSold, 300);
      expect(report.grossProfit, 700);
      expect(report.expenses, 200);
      expect(report.netProfit, 500);
    });
  });

  group('date-boundary audit (bug fix)', () {
    // Regression test for the exact symptom the Reports audit set out
    // to trace ("Revenue: ₦7,500 while Money in from sales: ₦0"):
    // dateTo used to be compared against raw, with no end-of-day
    // normalization. A "Today" period has dateFrom == dateTo == bare
    // midnight (see ReportPeriod.end), so any sale later that same day
    // — like this one, at 2pm — used to fall outside
    // `saleDate.isSmallerOrEqualValue(dateTo)` entirely.
    test('a sale later the same day as dateTo is still included, not '
        'silently excluded by a bare-midnight upper bound', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15, 14, 30), // 2:30pm
        total: 7500,
        amountPaid: 7500,
        items: const [],
      );

      // "Today" for Jan 15 — both bounds bare midnight, exactly like
      // ReportPeriod.end for ReportPeriodKind.today.
      final cashFlow = await repository.getCashFlow(
        dateFrom: DateTime(2026, 1, 15),
        dateTo: DateTime(2026, 1, 15),
        locationId: 'loc-1',
      );
      expect(cashFlow.salesInflow, 7500);

      final profitLoss = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 15),
        dateTo: DateTime(2026, 1, 15),
        locationId: 'loc-1',
      );
      expect(profitLoss.revenue, 7500);
    });
  });

  group('void/refund audit (bug fix)', () {
    test('getCashFlow: a voided sale contributes no cash inflow', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: const [],
      );
      await db.into(db.returnRequests).insert(
            ReturnRequestsCompanion.insert(
              localId: 'return-1',
              originalSaleLocalId: 'sale-voided',
              status: 'completed',
              returnReason: 'Test',
              refundAmount: 1000,
              refundMethod: 'cash',
              isVoid: const Value(true),
              createdAt: DateTime(2026, 1, 15),
              updatedAt: DateTime(2026, 1, 15),
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getCashFlow(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.salesInflow, 0);
      expect(report.inflow, 0);
    });

    test('getProfitLoss: a voided sale contributes no revenue', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-voided',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: const [],
      );
      await db.into(db.returnRequests).insert(
            ReturnRequestsCompanion.insert(
              localId: 'return-1',
              originalSaleLocalId: 'sale-voided',
              status: 'completed',
              returnReason: 'Test',
              refundAmount: 1000,
              refundMethod: 'cash',
              isVoid: const Value(true),
              createdAt: DateTime(2026, 1, 15),
              updatedAt: DateTime(2026, 1, 15),
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getProfitLoss(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.revenue, 0);
    });
  });

  group('getCashFlow', () {
    test('combines sales and manual income into inflow', () async {
      await insertLocation('loc-1');
      await insertCompletedSale(
        localId: 'sale-1',
        locationId: 'loc-1',
        saleDate: DateTime(2026, 1, 15),
        total: 1000,
        amountPaid: 1000,
        items: const [],
      );
      await db.into(db.incomeRecords).insert(
            IncomeRecordsCompanion.insert(
              localId: 'income-1',
              locationId: 'loc-1',
              source: 'Old equipment sold',
              amount: 300,
              incomeDate: DateTime(2026, 1, 10),
              createdAt: DateTime(2026, 1, 10),
              updatedAt: DateTime(2026, 1, 10),
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getCashFlow(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.salesInflow, 1000);
      expect(report.manualIncomeInflow, 300);
      expect(report.inflow, 1300);
    });

    test('combines expenses and supplier payments into outflow', () async {
      await insertLocation('loc-1');
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              localId: 'supplier-1',
              name: 'Test Supplier',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              syncStatus: SyncStatus.settled,
            ),
          );
      await db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              localId: 'expense-1',
              locationId: 'loc-1',
              description: 'Utilities',
              amount: 150,
              expenseDate: DateTime(2026, 1, 12),
              createdAt: DateTime(2026, 1, 12),
              updatedAt: DateTime(2026, 1, 12),
              syncStatus: SyncStatus.settled,
            ),
          );
      await db.into(db.supplierLedgerEntries).insert(
            SupplierLedgerEntriesCompanion.insert(
              localId: 'sle-1',
              supplierLocalId: 'supplier-1',
              entryType: 'paymentMade',
              amount: 400,
              createdAt: DateTime(2026, 1, 20),
            ),
          );

      final report = await repository.getCashFlow(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.expensesOutflow, 150);
      expect(report.supplierPaymentsOutflow, 400);
      expect(report.outflow, 550);
    });

    // Regression test for a confirmed bug (Reports & Auditability
    // upgrade): inflow used to only ever sum salesInflow +
    // manualIncomeInflow, silently omitting every customer repayment —
    // see CashFlowReport.customerRepaymentsInflow's own doc comment.
    test('a customer repayment counts toward inflow, not just sales and '
        'manual income', () async {
      await insertLocation('loc-1');
      await db.into(db.customers).insert(
            CustomersCompanion.insert(
              localId: 'customer-1',
              name: 'Test Customer',
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
        items: const [],
      );
      await db.into(db.customerLedgerEntries).insert(
            CustomerLedgerEntriesCompanion.insert(
              localId: 'cle-1',
              customerLocalId: 'customer-1',
              entryType: 'repayment',
              amount: 250,
              createdAt: DateTime(2026, 1, 18),
              updatedAt: DateTime(2026, 1, 18),
              syncStatus: SyncStatus.settled,
            ),
          );
      // A creditSale entry in the same period must NOT be counted here
      // — it isn't cash moving, it's the debt being created in the
      // first place. Only 'repayment' entries are real inflow.
      await db.into(db.customerLedgerEntries).insert(
            CustomerLedgerEntriesCompanion.insert(
              localId: 'cle-2',
              customerLocalId: 'customer-1',
              entryType: 'creditSale',
              amount: 999,
              createdAt: DateTime(2026, 1, 19),
              updatedAt: DateTime(2026, 1, 19),
              syncStatus: SyncStatus.settled,
            ),
          );

      final report = await repository.getCashFlow(
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
        locationId: 'loc-1',
      );

      expect(report.customerRepaymentsInflow, 250);
      expect(report.inflow, 1000 + 250);
    });
  });
}
