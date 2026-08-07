import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/repositories/finance_stats_repository_impl.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FinanceStatsRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = FinanceStatsRepositoryImpl(db: db);
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
  });
}
